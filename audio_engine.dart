import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import '../models/studio_models.dart';

class AudioEngine {
  /// Reads the user-selected reference voice audio directly in pure Dart.
  Future<Uint8List> prepareReferenceVoice(
    File sourceFile,
    Directory tempDir,
  ) async {
    final bytes = await sourceFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const AppError('The selected audio file is empty.');
    }
    return bytes;
  }

  /// Normalizes synthesized audio (WAV, raw PCM16, or MP3) in pure Dart.
  Future<void> normalizeToWav({
    required Uint8List audioBytes,
    required String contentType,
    required SpeechModel model,
    required File destination,
    required Directory tempDir,
    double? previewSpeed,
    bool previewNormalize = false,
  }) async {
    if (audioBytes.isEmpty) {
      throw const AppError(
        'The model returned empty audio. Retry this section.',
      );
    }

    await destination.parent.create(recursive: true);

    final isWav = _isWav(audioBytes);
    final isPcm = contentType.contains('pcm') ||
        (model.format == 'pcm' && !_hasContainerHeader(audioBytes));

    if (isPcm) {
      final rateMatch =
          RegExp(r'(?:rate|samplerate)\s*=\s*(\d+)').firstMatch(contentType);
      final chMatch = RegExp(r'channels\s*=\s*(\d+)').firstMatch(contentType);
      final rawRate = rateMatch != null
          ? int.parse(rateMatch.group(1)!)
          : (model.sampleRate ?? 44100);
      final channels = chMatch != null ? int.parse(chMatch.group(1)!) : 1;

      if (rawRate < 8000 || rawRate > 192000 || (channels != 1 && channels != 2)) {
        throw const AppError(
          'The provider returned PCM without a usable sample rate. Refresh models or use Fish Audio.',
        );
      }
      if (audioBytes.length % (2 * channels) != 0) {
        throw const AppError(
          'The provider returned incomplete PCM audio. Retry this section.',
        );
      }

      final pcmBytes =
          previewNormalize ? _normalizePcm16(audioBytes) : audioBytes;
      final header = _buildWavHeader(
        dataSize: pcmBytes.length,
        sampleRate: rawRate,
        channels: channels,
        bitsPerSample: 16,
      );
      final out = BytesBuilder(copy: false)
        ..add(header)
        ..add(pcmBytes);
      await destination.writeAsBytes(out.takeBytes(), flush: true);
    } else if (isWav && previewNormalize) {
      await destination.writeAsBytes(audioBytes, flush: true);
      final info = await _parseWavHeader(destination);
      if (info != null && info.bitsPerSample == 16 && info.dataSize > 0) {
        final pcm = audioBytes.sublist(
          info.dataOffset,
          min(audioBytes.length, info.dataOffset + info.dataSize),
        );
        final norm = _normalizePcm16(pcm);
        final header = _buildWavHeader(
          dataSize: norm.length,
          sampleRate: info.sampleRate,
          channels: info.channels,
          bitsPerSample: 16,
        );
        final out = BytesBuilder(copy: false)
          ..add(header)
          ..add(norm);
        await destination.writeAsBytes(out.takeBytes(), flush: true);
      }
    } else {
      // MP3 or already-encoded container audio — store directly for playback and stitching.
      await destination.writeAsBytes(audioBytes, flush: true);
    }

    final dur = await wavDuration(destination);
    if (dur < 0.05) {
      throw const AppError(
        'The model returned empty or very short audio. Retry this section.',
      );
    }
  }

  /// Joins audio sections in pure Dart (WAV PCM16 stitching with silence & loudness balance,
  /// or frame-clean MP3 concatenation) and writes narration.wav and narration.mp3 into [exportDir].
  Future<double> joinAndExport({
    required List<File> chunkFiles,
    required Directory exportDir,
    required Directory tempDir,
    required double pauseSeconds,
    required double speed,
    required bool normalize,
  }) async {
    await exportDir.create(recursive: true);
    final wavOut = File('${exportDir.path}/narration.wav');
    final mp3Out = File('${exportDir.path}/narration.mp3');

    if (chunkFiles.isEmpty) {
      throw const AppError('No audio sections available to export.');
    }

    final firstHead = await _parseWavHeader(chunkFiles.first);
    if (firstHead != null) {
      await _concatWavs(
        files: chunkFiles,
        output: wavOut,
        pauseSeconds: pauseSeconds,
        normalize: normalize,
      );
      await wavOut.copy(mp3Out.path);
      return await wavDuration(wavOut);
    } else {
      await _concatMp3s(chunkFiles, mp3Out);
      await mp3Out.copy(wavOut.path);
      return await wavDuration(mp3Out);
    }
  }

  /// Creates narration_bundle.zip with full mixes, script, settings, and per-section audio/text.
  Future<File> createBundle({
    required Directory exportDir,
    required Directory projectDir,
    required List<ScriptChunk> chunks,
  }) async {
    final bundleFile = File('${exportDir.path}/narration_bundle.zip');
    final encoder = ZipFileEncoder()..create(bundleFile.path);

    for (final name in const [
      'narration.mp3',
      'narration.wav',
      'script.txt',
      'settings.json',
    ]) {
      final f = File('${exportDir.path}/$name');
      if (await f.exists()) {
        await encoder.addFile(f, name);
      }
    }

    for (final chunk in chunks) {
      final idx = chunk.index.toString().padLeft(3, '0');
      final wav = File('${projectDir.path}/${chunk.path}');
      if (await wav.exists()) {
        await encoder.addFile(wav, 'sections/section_$idx.wav');
      }
      final txtBytes = utf8.encode(chunk.text);
      encoder.addArchiveFile(
        ArchiveFile('sections/section_$idx.txt', txtBytes.length, txtBytes),
      );
    }

    encoder.close();
    return bundleFile;
  }

  /// Pure-Dart audio duration reader (exact for WAV, bitrate estimate for MP3).
  Future<double> wavDuration(File audioFile) async {
    if (!await audioFile.exists()) return 0;
    final info = await _parseWavHeader(audioFile);
    if (info != null && info.byteRate > 0) {
      return info.dataSize / info.byteRate;
    }
    final size = await audioFile.length();
    if (size < 128) return 0;
    // Estimate MP3 duration assuming ~128 kbps (16,000 bytes/sec)
    return max(0.2, size / 16000.0);
  }

  /// Pure-Dart peak envelope extractor (exact for 16-bit WAV, smooth envelope for MP3).
  Future<List<double>> extractWaveformPeaks(
    File audioFile, {
    int count = 256,
  }) async {
    final info = await _parseWavHeader(audioFile);
    if (info != null && info.bitsPerSample == 16 && info.dataSize > 0) {
      final raf = await audioFile.open();
      try {
        final totalFrames = info.dataSize ~/ (info.channels * 2);
        if (totalFrames <= 0) return List<double>.filled(count, 0.15);

        final rawPeaks = List<int>.filled(count, 0);
        var largest = 1;

        for (var i = 0; i < count; i++) {
          final startFrame = (totalFrames * i) ~/ count;
          final endFrame = (totalFrames * (i + 1)) ~/ count;
          final framesToRead = max(1, min(endFrame - startFrame, 4096));
          final byteOffset = info.dataOffset + startFrame * info.channels * 2;
          final byteLen = min(
            framesToRead * info.channels * 2,
            info.dataOffset + info.dataSize - byteOffset,
          );
          if (byteLen < 2) continue;

          await raf.setPosition(byteOffset);
          final bytes = await raf.read(byteLen);
          final data = ByteData.sublistView(bytes);
          var peak = 0;
          for (var pos = 0; pos + 1 < bytes.length; pos += 2) {
            final sample = data.getInt16(pos, Endian.little).abs();
            if (sample > peak) peak = sample;
          }
          rawPeaks[i] = peak;
          if (peak > largest) largest = peak;
        }

        return rawPeaks
            .map((v) => double.parse(pow(v / largest, 0.78).toStringAsFixed(3)))
            .toList();
      } finally {
        await raf.close();
      }
    }

    // Fallback visual envelope for compressed MP3 audio
    if (!await audioFile.exists()) return List<double>.filled(count, 0.2);
    final bytes = await audioFile.readAsBytes();
    if (bytes.length < count) return List<double>.filled(count, 0.25);
    final step = bytes.length ~/ count;
    final peaks = <double>[];
    for (var i = 0; i < count; i++) {
      final start = i * step;
      final end = min(start + min(step, 512), bytes.length);
      var energy = 0.0;
      for (var j = start; j < end; j++) {
        energy += (bytes[j] - 128).abs();
      }
      final avg = (energy / max(1, end - start)) / 128.0;
      peaks.add(avg.clamp(0.12, 0.95));
    }
    return peaks;
  }

  Future<void> _concatWavs({
    required List<File> files,
    required File output,
    required double pauseSeconds,
    required bool normalize,
  }) async {
    final first = await _parseWavHeader(files.first);
    if (first == null) {
      throw const AppError('Could not read WAV header for export.');
    }

    final sampleRate = first.sampleRate;
    final channels = first.channels;
    final bitsPerSample = first.bitsPerSample;
    final bytesPerFrame = channels * (bitsPerSample ~/ 8);
    final silenceBytes = (sampleRate * pauseSeconds).round() * bytesPerFrame;
    final silence = Uint8List(silenceBytes);

    final pcmBuilder = BytesBuilder(copy: false);
    for (var i = 0; i < files.length; i++) {
      if (i > 0 && silenceBytes > 0) {
        pcmBuilder.add(silence);
      }
      final info = await _parseWavHeader(files[i]);
      if (info == null) continue;
      final all = await files[i].readAsBytes();
      final end = min(all.length, info.dataOffset + info.dataSize);
      if (end > info.dataOffset) {
        pcmBuilder.add(all.sublist(info.dataOffset, end));
      }
    }

    var pcm = pcmBuilder.takeBytes();
    if (normalize && bitsPerSample == 16 && pcm.length >= 2) {
      pcm = _normalizePcm16(pcm);
    }

    final header = _buildWavHeader(
      dataSize: pcm.length,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    );
    final out = BytesBuilder(copy: false)
      ..add(header)
      ..add(pcm);
    await output.writeAsBytes(out.takeBytes(), flush: true);
  }

  Future<void> _concatMp3s(List<File> files, File output) async {
    final sink = output.openWrite();
    try {
      for (var i = 0; i < files.length; i++) {
        final bytes = await files[i].readAsBytes();
        if (bytes.isEmpty) continue;
        if (i == 0) {
          sink.add(bytes);
        } else {
          final offset = _stripId3v2Offset(bytes);
          sink.add(offset > 0 ? bytes.sublist(offset) : bytes);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  int _stripId3v2Offset(Uint8List bytes) {
    if (bytes.length < 10) return 0;
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      // Synchsafe 28-bit size
      final size = ((bytes[6] & 0x7F) << 21) |
          ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) |
          (bytes[9] & 0x7F);
      return min(bytes.length, 10 + size);
    }
    return 0;
  }

  Uint8List _normalizePcm16(Uint8List pcm) {
    final count = pcm.length ~/ 2;
    if (count == 0) return pcm;
    final src = ByteData.sublistView(pcm);
    var sumSq = 0.0;
    var peak = 1;
    for (var i = 0; i < count; i++) {
      final s = src.getInt16(i * 2, Endian.little);
      final a = s.abs();
      if (a > peak) peak = a;
      sumSq += s * s;
    }
    final rms = sqrt(sumSq / count);
    if (rms < 1.0) return pcm;

    // Target ~ -16 dBFS (RMS ~ 5200) while preventing clipping above 0.95 full-scale
    const targetRms = 5200.0;
    final maxGain = (32767 * 0.95) / peak;
    final gain = min(targetRms / rms, maxGain).clamp(0.25, 4.0);

    final out = Uint8List(pcm.length);
    final dst = ByteData.sublistView(out);
    for (var i = 0; i < count; i++) {
      final s = src.getInt16(i * 2, Endian.little);
      final scaled = (s * gain).round().clamp(-32768, 32767);
      dst.setInt16(i * 2, scaled, Endian.little);
    }
    return out;
  }

  bool _isWav(Uint8List b) {
    return b.length >= 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WAVE';
  }

  bool _hasContainerHeader(Uint8List b) {
    if (b.length < 4) return false;
    final head = String.fromCharCodes(b.sublist(0, 4));
    return head == 'RIFF' ||
        head.startsWith('ID3') ||
        head == 'OggS' ||
        head == 'fLaC' ||
        (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0);
  }

  Uint8List _buildWavHeader({
    required int dataSize,
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final buf = ByteData(44);
    buf.setUint32(0, 0x52494646, Endian.big); // RIFF
    buf.setUint32(4, 36 + dataSize, Endian.little);
    buf.setUint32(8, 0x57415645, Endian.big); // WAVE
    buf.setUint32(12, 0x666d7420, Endian.big); // fmt
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20, 1, Endian.little); // PCM
    buf.setUint16(22, channels, Endian.little);
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, byteRate, Endian.little);
    buf.setUint16(32, blockAlign, Endian.little);
    buf.setUint16(34, bitsPerSample, Endian.little);
    buf.setUint32(36, 0x64617461, Endian.big); // data
    buf.setUint32(40, dataSize, Endian.little);
    return buf.buffer.asUint8List();
  }

  Future<_WavInfo?> _parseWavHeader(File file) async {
    if (!await file.exists()) return null;
    final raf = await file.open();
    try {
      final length = await raf.length();
      if (length < 44) return null;
      final head = await raf.read(12);
      if (String.fromCharCodes(head.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(head.sublist(8, 12)) != 'WAVE') {
        return null;
      }

      var channels = 1;
      var sampleRate = 44100;
      var byteRate = 88200;
      var bitsPerSample = 16;
      var pos = 12;

      while (pos + 8 <= length) {
        await raf.setPosition(pos);
        final chunkHeader = await raf.read(8);
        final id = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final size =
            ByteData.sublistView(chunkHeader).getUint32(4, Endian.little);
        pos += 8;

        if (id == 'fmt ' && size >= 16) {
          final fmt = await raf.read(16);
          final bd = ByteData.sublistView(fmt);
          channels = bd.getUint16(2, Endian.little);
          sampleRate = bd.getUint32(4, Endian.little);
          byteRate = bd.getUint32(8, Endian.little);
          bitsPerSample = bd.getUint16(14, Endian.little);
        } else if (id == 'data') {
          return _WavInfo(
            channels: channels,
            sampleRate: sampleRate,
            byteRate: byteRate,
            bitsPerSample: bitsPerSample,
            dataOffset: pos,
            dataSize: min(size, length - pos),
          );
        }
        pos += size + (size.isOdd ? 1 : 0);
      }
      return null;
    } finally {
      await raf.close();
    }
  }
}

class _WavInfo {
  final int channels;
  final int sampleRate;
  final int byteRate;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;

  const _WavInfo({
    required this.channels,
    required this.sampleRate,
    required this.byteRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
  });
}
