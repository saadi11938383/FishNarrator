import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/studio_models.dart';

final RegExp _bracketTags = RegExp(r'\[[^\]]*\]');
final RegExp _sentBoundary = RegExp(
  r'''(?<=[.!?…。！？؟۔]["'”’)\]])\s+|(?<=[.!?…。！？؟۔])\s+''',
);
final RegExp _longUnits = RegExp(r'(?<=[.!?…。！？])\s+|\n\s*\n');
final RegExp _tokenRegex = RegExp(r'\S+\s*');

int wordCount(String text) {
  final cleaned = text.replaceAll(_bracketTags, ' ').trim();
  if (cleaned.isEmpty) return 0;
  return cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

Object? _sortKeys(Object? value) {
  if (value is Map) {
    final sorted = <String, Object?>{};
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    for (final key in keys) {
      sorted[key] = _sortKeys(value[key]);
    }
    return sorted;
  }
  if (value is List) {
    return value.map(_sortKeys).toList();
  }
  return value;
}

String sha256Digest(Object value) {
  final bytes = value is List<int>
      ? value
      : utf8.encode(jsonEncode(_sortKeys(value)));
  return sha256.convert(bytes).toString();
}

List<String> _paragraphChunks(String text, int target) {
  final normalized =
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (normalized.isEmpty) return [];

  final paras = normalized
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' ').trim())
      .where((p) => p.isNotEmpty)
      .toList();

  final units = <(String, bool)>[];
  for (final p in paras) {
    final sents = _sentBoundary
        .split(p)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    for (var i = 0; i < sents.length; i++) {
      units.add((sents[i], i == sents.length - 1));
    }
  }

  final rest = List<int>.filled(units.length, 0);
  var acc = 0;
  for (var i = units.length - 1; i >= 0; i--) {
    if (units[i].$2) {
      acc = 0;
    }
    acc += wordCount(units[i].$1);
    rest[i] = acc;
  }

  final chunks = <List<(String, bool)>>[];
  var cur = <(String, bool)>[];
  var cw = 0;

  for (var i = 0; i < units.length; i++) {
    final (s, pend) = units[i];
    final w = wordCount(s);
    final paraStart = i == 0 || units[i - 1].$2;
    if (cur.isNotEmpty &&
        (cw + w > target ||
            (paraStart && cw + rest[i] > target && cw >= 0.5 * target))) {
      chunks.add(cur);
      cur = [];
      cw = 0;
    }
    cur.add((s, pend));
    cw += w;
  }
  if (cur.isNotEmpty) {
    chunks.add(cur);
  }

  return chunks.map((chunk) {
    final buffer = StringBuffer();
    for (final (s, pend) in chunk) {
      buffer.write(s);
      buffer.write(pend ? '\n\n' : ' ');
    }
    return buffer.toString().trim();
  }).toList();
}

List<String> _splitLong(String text, int target, int maxChars) {
  final normalized =
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (normalized.isEmpty) return [];

  final units = _longUnits.split(normalized);
  final chunks = <String>[];
  var current = '';

  for (final rawSentence in units) {
    final sentence = rawSentence.trim();
    if (sentence.isEmpty) continue;

    var pieces = <String>[sentence];
    if (sentence.length > maxChars || wordCount(sentence) > target) {
      pieces = <String>[];
      var piece = '';
      for (final match in _tokenRegex.allMatches(sentence)) {
        final token = match.group(0)!;
        for (var start = 0; start < token.length; start += maxChars) {
          final part =
              token.substring(start, min(start + maxChars, token.length));
          if (piece.isNotEmpty &&
              ((piece + part).length > maxChars ||
                  wordCount(piece + part) > target)) {
            pieces.add(piece.trim());
            piece = '';
          }
          piece += part;
        }
      }
      if (piece.trim().isNotEmpty) {
        pieces.add(piece.trim());
      }
    }

    for (final piece in pieces) {
      final candidate = current.isEmpty ? piece : '$current $piece'.trim();
      if (current.isNotEmpty &&
          (candidate.length > maxChars || wordCount(candidate) > target)) {
        chunks.add(current);
        current = piece;
      } else {
        current = candidate;
      }
    }
  }
  if (current.isNotEmpty) {
    chunks.add(current);
  }
  return chunks;
}

List<String> splitScript(String text, {int target = 280, int maxChars = 3000}) {
  final chunks = <String>[];
  for (final candidate in _paragraphChunks(text, target)) {
    if (candidate.length <= maxChars && wordCount(candidate) <= target) {
      chunks.add(candidate);
    } else {
      chunks.addAll(_splitLong(candidate, target, maxChars));
    }
  }
  return chunks;
}

NarrationPlan buildNarrationPlan({
  required String script,
  required VoiceSettings settings,
  required SpeechModel model,
  Directory? projectDir,
}) {
  final texts = splitScript(
    script,
    target: settings.chunkWords,
    maxChars: model.maxChars,
  );

  final synthesis = <String, dynamic>{
    'model': settings.model,
    'voice': settings.voiceMode == 'clone' ? '' : settings.voice,
    'voice_mode': settings.voiceMode,
    'reference': settings.voiceMode == 'clone' ? settings.reference : '',
    'reference_text': (settings.voiceMode == 'clone' && model.transcript)
        ? settings.referenceText
        : '',
    'instructions': model.instructions ? settings.instructions : '',
  };

  final chunks = <ScriptChunk>[];
  final occurrences = <String, int>{};

  for (var i = 0; i < texts.length; i++) {
    final text = texts[i];
    final occurrence = occurrences[text] ?? 0;
    occurrences[text] = occurrence + 1;
    final signature = sha256Digest({
      'text': text,
      'settings': synthesis,
      'occurrence': occurrence,
    });
    final relative = 'chunks/$signature.wav';
    final cached = projectDir != null &&
        File('${projectDir.path}/$relative').existsSync();
    chunks.add(ScriptChunk(
      index: i + 1,
      text: text,
      words: wordCount(text),
      chars: text.length,
      signature: signature,
      path: relative,
      cached: cached,
    ));
  }

  ScriptChunk? preview;
  if (texts.isNotEmpty) {
    final previewText = splitScript(
      texts.first,
      target: 45,
      maxChars: min(600, model.maxChars),
    ).first;
    final previewSig = sha256Digest({
      'preview': previewText,
      'settings': synthesis,
      'speed': settings.speed,
      'normalize': settings.normalize,
    });
    final relative = 'previews/$previewSig.wav';
    final cached = projectDir != null &&
        File('${projectDir.path}/$relative').existsSync();
    preview = ScriptChunk(
      index: 1,
      text: previewText,
      words: wordCount(previewText),
      chars: previewText.length,
      signature: previewSig,
      path: relative,
      cached: cached,
    );
  }

  final words = wordCount(script);
  final estimatedSeconds = ((words / 2.5 +
              max(0, chunks.length - 1) * settings.pause) /
          settings.speed)
      .round();

  return NarrationPlan(
    chunks: chunks,
    preview: preview,
    requests: chunks.where((c) => !c.cached).length,
    estimatedSeconds: estimatedSeconds,
  );
}
