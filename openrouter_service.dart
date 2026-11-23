import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/studio_models.dart';

class SynthesisAudio {
  final Uint8List bytes;
  final String contentType;
  const SynthesisAudio(this.bytes, this.contentType);
}

class OpenRouterService {
  static const String apiBase = 'https://openrouter.ai/api/v1';
  static const String catalogDate = '2026-11-22';

  final http.Client _client;
  final File? _cacheFile;

  List<Map<String, dynamic>> _rawModels = [];
  String _source = 'bundled';
  String _asOf = catalogDate;
  String _error = '';
  DateTime? _lastChecked;

  OpenRouterService({http.Client? client, File? cacheFile})
      : _client = client ?? http.Client(),
        _cacheFile = cacheFile;

  Map<String, String> _headers(String key) => {
        'Authorization': 'Bearer $key',
        'HTTP-Referer': 'https://fishnarrator.app/mobile',
        'X-Title': 'FishNarrator v2 Mobile',
      };

  static bool isFreeSpeech(Map<String, dynamic> model) {
    final pricing = (model['pricing'] as Map?)?.cast<String, dynamic>();
    final arch = (model['architecture'] as Map?)?.cast<String, dynamic>();
    final modalities = (arch?['output_modalities'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final id = model['id']?.toString() ?? '';
    if (!modalities.contains('speech') || !id.endsWith(':free')) {
      return false;
    }
    if (pricing == null ||
        !pricing.containsKey('prompt') ||
        !pricing.containsKey('completion')) {
      return false;
    }
    for (final value in pricing.values) {
      final parsed = double.tryParse(value.toString());
      if (parsed == null || parsed != 0.0) return false;
    }
    return true;
  }

  Future<void> initCatalog() async {
    if (_cacheFile != null && await _cacheFile.exists()) {
      try {
        final payload =
            jsonDecode(await _cacheFile.readAsString()) as Map<String, dynamic>;
        final data = (payload['data'] as List).cast<Map<String, dynamic>>();
        _rawModels = data;
        _asOf = payload['as_of']?.toString() ?? catalogDate;
        _source = 'cached';
        return;
      } catch (_) {}
    }

    try {
      final seedStr = await rootBundle.loadString('assets/catalog_seed.json');
      final payload = jsonDecode(seedStr) as Map<String, dynamic>;
      _rawModels = (payload['data'] as List).cast<Map<String, dynamic>>();
      _asOf = payload['as_of']?.toString() ?? catalogDate;
      _source = 'bundled';
    } catch (_) {
      _rawModels = [];
    }
  }

  CatalogSnapshot snapshot() {
    final items = _rawModels
        .where(isFreeSpeech)
        .map(SpeechModel.describe)
        .toList()
      ..sort((a, b) {
        final aDef = a.id == SpeechModel.defaultModelId ? 0 : 1;
        final bDef = b.id == SpeechModel.defaultModelId ? 0 : 1;
        if (aDef != bDef) return aDef.compareTo(bDef);
        return a.name.compareTo(b.name);
      });
    return CatalogSnapshot(
      models: items,
      source: _source,
      asOf: _asOf,
      error: _error,
    );
  }

  Future<CatalogSnapshot> refreshCatalog({bool force = false}) async {
    if (!force &&
        _lastChecked != null &&
        DateTime.now().difference(_lastChecked!).inSeconds < 300) {
      return snapshot();
    }
    try {
      final uri =
          Uri.parse('$apiBase/models').replace(queryParameters: {'output_modalities': 'speech'});
      final response = await _client.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AppError('Could not load speech models.');
      }
      var payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['data'] is! List) {
        throw const AppError('Invalid model catalog.');
      }
      final raw = List<Map<String, dynamic>>.from(
        (payload['data'] as List).map((e) => (e as Map).cast<String, dynamic>()),
      );

      var nextUrl = (payload['links'] as Map?)?['next']?.toString();
      final visited = <String>{};
      while (nextUrl != null && nextUrl.isNotEmpty) {
        if (visited.contains(nextUrl) || !nextUrl.startsWith('$apiBase/models?')) {
          break;
        }
        visited.add(nextUrl);
        final page = await _client
            .get(Uri.parse(nextUrl))
            .timeout(const Duration(seconds: 20));
        if (page.statusCode < 200 || page.statusCode >= 300) break;
        payload = jsonDecode(page.body) as Map<String, dynamic>;
        raw.addAll(
          (payload['data'] as List).map((e) => (e as Map).cast<String, dynamic>()),
        );
        nextUrl = (payload['links'] as Map?)?['next']?.toString();
      }

      _rawModels = raw.where(isFreeSpeech).toList();
      final extra = _rawModels
          .where((m) =>
              m['id'] != SpeechModel.defaultModelId &&
              m['id'] != SpeechModel.heygenModelId)
          .toList();
      if (extra.isNotEmpty) {
        await _enrichParameters(extra);
      }

      _asOf = DateTime.now().toIso8601String().substring(0, 10);
      _source = 'live';
      _error = '';
      _lastChecked = DateTime.now();

      if (_cacheFile != null) {
        await _cacheFile.parent.create(recursive: true);
        await _cacheFile.writeAsString(
          jsonEncode({'data': _rawModels, 'as_of': _asOf}),
        );
      }
    } catch (_) {
      _source = 'cached';
      _error =
          'Model refresh failed. Showing the saved catalog. Check your connection and refresh.';
    }
    return snapshot();
  }

  Future<void> _enrichParameters(List<Map<String, dynamic>> models) async {
    try {
      final resp = await _client
          .get(Uri.parse('$apiBase/audio/speech/models'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final details = <String, Map<String, dynamic>>{};
      for (final row in (body['data'] as List? ?? const [])) {
        final m = (row as Map).cast<String, dynamic>();
        if (m['id'] != null) details[m['id'].toString()] = m;
      }
      for (final model in models) {
        final id = model['id'].toString();
        final baseId = id.endsWith(':free') ? id.substring(0, id.length - 5) : id;
        final detail = details[id] ?? details[baseId] ?? const <String, dynamic>{};
        for (final entry in (detail['output_modalities'] as List? ?? const [])) {
          final e = (entry as Map).cast<String, dynamic>();
          if (e['type'] == 'speech') {
            model['speech_params'] = e['supported_parameters'] ?? const {};
          }
        }
        final inputs = (detail['input_modalities'] as List? ?? const []);
        if (inputs.any((x) => (x as Map)['type'] == 'audio')) {
          final ep = await _client
              .get(Uri.parse('$apiBase/models/$id/endpoints'))
              .timeout(const Duration(seconds: 8));
          if (ep.statusCode >= 200 && ep.statusCode < 300) {
            final epData = jsonDecode(ep.body) as Map<String, dynamic>;
            final endpoints =
                ((epData['data'] as Map?)?['endpoints'] as List?) ?? const [];
            model['can_clone'] = endpoints.any(
              (e) => (e as Map)['supports_voice_cloning'] == true,
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<SpeechModel> getModel(
    String modelId, {
    bool live = false,
    bool forPlan = false,
  }) async {
    if (live) {
      await refreshCatalog(force: true);
    }
    SpeechModel? found;
    for (final m in snapshot().models) {
      if (m.id == modelId) {
        found = m;
        break;
      }
    }
    if (found == null && forPlan && modelId.endsWith(':free')) {
      found = SpeechModel.describe({'id': modelId});
    }
    if (found == null) {
      throw const AppError(
        'This model is absent from the free speech catalog. Refresh models and choose an available model.',
      );
    }
    if (!found.available && !forPlan) {
      throw const AppError(
        'This model\'s free listing has expired. Refresh models and choose another model.',
      );
    }
    return found;
  }

  Future<AccountStatus> checkAccount(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return const AccountStatus(configured: false);
    }
    try {
      final resp = await _client
          .get(Uri.parse('$apiBase/key'), headers: _headers(trimmed))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw AppError(
          'Could not check your key (${resp.statusCode}). ${_extractError(resp.body, trimmed)}',
        );
      }
      final payload = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = (payload['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final free = (data['free_model_daily_requests'] as Map?)?.cast<String, dynamic>();
      return AccountStatus(
        configured: true,
        valid: true,
        freeRequests: free,
        note: free == null
            ? 'OpenRouter did not return a daily request count.'
            : '',
      );
    } on AppError {
      rethrow;
    } catch (_) {
      throw const AppError(
        'Could not reach OpenRouter to check the key. Check your connection.',
      );
    }
  }

  Future<SynthesisAudio> synthesize({
    required String key,
    required SpeechModel model,
    required String text,
    required VoiceSettings settings,
    Uint8List? referenceBytes,
    required bool Function() isStopped,
    required void Function(String message) onLog,
  }) async {
    final body = <String, dynamic>{
      'model': model.id,
      'input': text,
      'response_format': model.format,
    };

    if (referenceBytes != null && referenceBytes.isNotEmpty) {
      final refs = <Map<String, dynamic>>[
        {
          'type': 'input_audio',
          'input_audio': {
            'data': 'data:audio/mpeg;base64,${base64Encode(referenceBytes)}',
          },
        },
      ];
      if (model.transcript && settings.referenceText.trim().isNotEmpty) {
        refs.add({'type': 'text', 'text': settings.referenceText.trim()});
      }
      body['input_references'] = refs;
    } else if (settings.voice.isNotEmpty) {
      body['voice'] = settings.voice;
    }

    if (model.instructions && settings.instructions.trim().isNotEmpty) {
      body['instructions'] = settings.instructions.trim();
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      if (isStopped()) {
        throw const StoppedError('Stopped. Finished sections are saved.');
      }
      try {
        final req = http.Request('POST', Uri.parse('$apiBase/audio/speech'))
          ..headers.addAll({
            ..._headers(key),
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode(body);

        final streamed =
            await _client.send(req).timeout(const Duration(seconds: 180));
        final contentType =
            (streamed.headers['content-type'] ?? '').toLowerCase();

        if (streamed.statusCode == 200 &&
            !contentType.contains('json') &&
            !contentType.contains('text/')) {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in streamed.stream) {
            builder.add(chunk);
            if (builder.length > 80 * 1024 * 1024) {
              throw const AppError(
                'The provider returned an unexpectedly large audio section.',
              );
            }
          }
          final bytes = builder.takeBytes();
          if (bytes.isEmpty) {
            throw const AppError(
              'The provider returned empty audio. Retry this section.',
            );
          }
          return SynthesisAudio(bytes, contentType);
        }

        final errorBody = await streamed.stream.bytesToString();
        final message = _extractError(errorBody, key);
        if (streamed.statusCode == 401) {
          throw const AppError(
            'OpenRouter rejected the API key. Open Settings and connect a valid key.',
          );
        }
        if (streamed.statusCode == 402) {
          throw const AppError(
            'OpenRouter refused this free request because of an account or credit restriction.',
          );
        }
        if (streamed.statusCode == 429 &&
            RegExp(r'daily|per.?day|day.?limit', caseSensitive: false)
                .hasMatch(message)) {
          throw const AppError(
            'Your daily free request limit has been reached. Finished sections are saved. Resume after your allowance resets.',
          );
        }

        const retryable = {408, 429, 500, 502, 503, 504};
        if (!retryable.contains(streamed.statusCode) || attempt == 2) {
          throw AppError('OpenRouter returned ${streamed.statusCode}. $message');
        }

        final retryHeader = streamed.headers['retry-after'] ?? '';
        final retrySeconds = int.tryParse(retryHeader);
        if (retrySeconds != null && retrySeconds > 120) {
          throw AppError(
            'OpenRouter asked you to wait $retrySeconds seconds. Your finished sections are saved.',
          );
        }
        final wait = (retrySeconds != null && retrySeconds > 3)
            ? retrySeconds
            : 10 * (attempt + 1);
        onLog('Provider busy. Retrying in $wait seconds (${attempt + 1}/2).');

        for (var s = 0; s < wait; s++) {
          if (isStopped()) {
            throw const StoppedError('Stopped. Finished sections are saved.');
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      } on AppError {
        rethrow;
      } catch (_) {
        throw const AppError(
          'The connection to OpenRouter was interrupted. Resume to retry the unfinished section.',
        );
      }
    }

    throw const AppError('Synthesis failed after retries.');
  }

  String _extractError(String body, String key) {
    var message = 'The provider returned an unexpected response.';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'] ?? decoded;
        message = (err is Map ? (err['message'] ?? err) : err).toString();
      }
    } catch (_) {}
    final scrubbed = message
        .replaceAll(key, '[key]')
        .replaceAll(RegExp(r'sk-or-[\w-]+'), '[key]');
    return scrubbed.length > 500 ? scrubbed.substring(0, 500) : scrubbed;
  }
}
