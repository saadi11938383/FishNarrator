import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../models/studio_models.dart';

class AudioEngine {
  Future<void> _runFfmpeg(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(
      ['-hide_banner', '-loglevel', 'error', '-y', ...args],
    );
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) {
      final logs = await session.getOutput() ?? '';
      final tail = logs.length > 300 ? logs.substring(logs.length - 300) : logs;
      throw AppError('Audio processing failed. $tail');
    }
  }

  /// Trims any user-selected reference voice audio to 30s, mono 44.1kHz 128k MP3.
  Future<Uint8List> prepareReferenceVoice(File sourceFile, Directory tempDir) async {
    final outFile = File('${tempDir.path}/ref_${DateTime.now().microsecondsSinceEpoch}.mp3');
    try {
      await _runFfmpeg([
        '-i', sourceFile.path,
        '-t', '30',
        '-vn',
        '-ac', '1',
        '-ar', '44100',
        '-b:a', '128k',
        outFile.path,
      ]);
      return await outFile.readAsBytes();
    } finally {
      if (await outFile.exists()) await outFile.delete();
    }
  }

  /// Normalizes synthesized audio (MP3, WAV, or raw PCM) to 44.1kHz mono 16-bit PCM WAV.
  Future<void> normalizeToWav({
    required Uint8List audioBytes,
    required String contentType,
    required SpeechModel model,
    required File destination,
    required Directory tempDir,
    double? previewSpeed,
    bool previewNormalize = false,
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final rawFile = File('${tempDir.path}/raw_$stamp.bin');
    final wavFile = File('${tempDir.path}/norm_$stamp.wav');
    final mixedFile = File('${tempDir.path}/mix_$stamp.wav');

    try {
      await rawFile.writeAsBytes(audioBytes, flush: true);

      final isPcm = contentType.contains('pcm') ||
          (model.format == 'pcm' && !_hasContainerHeader(audioBytes));

      final inputArgs = <String>[];
      if (isPcm) {
        final rateMatch =
            RegExp(r'(?:rate|samplerate)\s*=\s*(\d+)').firstMatch(contentType);
        final chMatch =
            RegExp(r'channels\s*=\s*(\d+)').firstMatch(contentType);
        final rawRate = rateMatch != null
            ? int.parse(rateMatch.group(1)!)
            : model.sampleRate;
        final channels = chMatch != null ? int.parse(chMatch.group(1)!) : 1;

        if (rawRate == null ||
            rawRate < 8000 ||
            rawRate > 192000 ||
            (channels != 1 && channels != 2)) {
          throw const AppError(
            'The provider returned PCM without a usable sample rate. Refresh models or use Fish Audio.',
          );
        }
        if (audioBytes.length % (2 * channels) != 0) {
          throw const AppError(
            'The provider returned incomplete PCM audio. Retry this section.',
          );
        }
        inputArgs.addAll(['-f', 's16le', '-ar', '$rawRate', '-ac', '$channels']);
      }

      await _runFfmpeg([
        ...inputArgs,
        '-i', rawFile.path,
        '-vn',
        '-ac', '1',
        '-ar', '44100',
        '-c:a', 'pcm_s16le',
        wavFile.path,
      ]);

      final dur = await wavDuration(wavFile);
      if (dur < 0.05) {
        throw const AppError(
          'The model returned empty or very short audio. Retry this section.',
        );
      }

      var finalFile = wavFile;
      if (previewSpeed != null && (previewSpeed != 1.0 || previewNormalize)) {
        final filters = <String>['atempo=${previewSpeed.toStringAsFixed(3)}'];
        if (previewNormalize) {
          filters.add('loudnorm=I=-16:TP=-1.5:LRA=11');
        }
        await _runFfmpeg([
          '-i', wavFile.path,
          '-af', filters.join(','),
          '-ar', '44100',
          '-ac', '1',
          '-c:a', 'pcm_s16le',
          mixedFile.path,
        ]);
        finalFile = mixedFile;
      }

      await destination.parent.create(recursive: true);
      await finalFile.copy(destination.path);
    } finally {
      for (final f in [rawFile, wavFile, mixedFile]) {
        if (await f.exists()) await f.delete();
      }
    }
  }

  /// Joins normalized 44.1kHz mono PCM16 WAV sections with silence, speed, and loudnorm,
  /// outputting narration.wav and narration.mp3 into [exportDir].
  Future<double> joinAndExport({
    required List<File> chunkFiles,
    required Directory exportDir,
    required Directory tempDir,
    required double pauseSeconds,
    required double speed,
    required bool normalize,
  }) async {
    await exportDir.create(recursive: true);
    final joinedFile =
        File('${tempDir.path}/joined_${DateTime.now().microsecondsSinceEpoch}.wav');
    final wavOut = File('${exportDir.path}/narration.wav');
    final mp3Out = File('${exportDir.path}/narration.mp3');

    try {
      await _concatNormalizedWavs(chunkFiles, joinedFile, pauseSeconds);

      final filters = <String>['atempo=${speed.toStringAsFixed(3)}'];
      if (normalize) {
        filters.add('loudnorm=I=-16:TP=-1.5:LRA=11');
      }

      await _runFfmpeg([
        '-i', joinedFile.path,
        '-af', filters.join(','),
        '-ar', '44100',
        '-ac', '1',
        '-c:a', 'pcm_s16le',
        wavOut.path,
      ]);

      await _runFfmpeg([
        '-i', wavOut.path,
        '-b:a', '192k',
        mp3Out.path,
      ]);

      return await wavDuration(wavOut);
    } finally {
      if (await joinedFile.exists()) await joinedFile.delete();
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

  /// Pure-Dart WAV duration reader (supports standard RIFF/WAVE PCM files).
  Future<double> wavDuration(File wavFile) async {
    final info = await _parseWavHeader(wavFile);
    if (info == null || info.byteRate <= 0) return 0;
    return info.dataSize / info.byteRate;
  }

  /// Pure-Dart peak envelope extractor (256 bars, gamma 0.78) matching engine.py.
  Future<List<double>> extractWaveformPeaks(File wavFile, {int count = 256}) async {
    final info = await _parseWavHeader(wavFile);
    if (info == null || info.bitsPerSample != 16 || info.dataSize <= 0) {
      return List<double>.filled(count, 0.15);
    }

    final raf = await wavFile.open();
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
        final byteLen =
            min(framesToRead * info.channels * 2, info.dataOffset + info.dataSize - byteOffset);
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

  Future<void> _concatNormalizedWavs(
    List<File> files,
    File output,
    double pauseSeconds,
  ) async {
    const sampleRate = 44100;
    const channels = 1;
    const bitsPerSample = 16;
    const bytesPerSample = 2;

    final silenceBytes = (sampleRate * pauseSeconds).round() * bytesPerSample;
    final silence = Uint8List(silenceBytes);

    var totalDataBytes = 0;
    final headers = <_WavInfo>[];
    for (var i = 0; i < files.length; i++) {
      final info = await _parseWavHeader(files[i]);
      if (info == null ||
          info.channels != channels ||
          info.bitsPerSample != bitsPerSample ||
          info.sampleRate != sampleRate) {
        throw const AppError(
          'A saved audio section has an incompatible format. Redo that section.',
        );
      }
      headers.add(info);
      totalDataBytes += info.dataSize;
      if (i > 0) totalDataBytes += silenceBytes;
    }

    final sink = output.openWrite();
    try {
      sink.add(_buildWavHeader(
        dataSize: totalDataBytes,
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
      ));
      for (var i = 0; i < files.length; i++) {
        if (i > 0 && silenceBytes > 0) {
          sink.add(silence);
        }
        final info = headers[i];
        await for (final block
            in files[i].openRead(info.dataOffset, info.dataOffset + info.dataSize)) {
          sink.add(block);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  bool _hasContainerHeader(Uint8List b) {
    if (b.length < 4) return false;
    final head = String.fromCharCodes(b.sublist(0, 4));
    return head == 'RIFF' ||
        head.startsWith('ID3') ||
        head == 'OggS' ||
        head == 'fLaC';
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
        final size = ByteData.sublistView(chunkHeader).getUint32(4, Endian.little);
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
