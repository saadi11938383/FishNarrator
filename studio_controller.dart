import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/studio_models.dart';
import 'audio_engine.dart';
import 'openrouter_service.dart';
import 'script_splitter.dart';

const String sampleScriptText =
    'The station clock stopped at midnight. Across the platform, a radio crackled. '
    'Then, through the static, a voice whispered my name.\n\n'
    'I looked up. The last train had already left. On the bench beside me, someone '
    'had drawn a little arrow in the dust. It pointed straight at the radio.\n\n'
    'I turned the dial one click. This time the voice was mine.';

class StudioController extends ChangeNotifier {
  static const _keyStorageName = 'openrouter_api_key';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final AudioEngine audioEngine = AudioEngine();
  final AudioPlayer player = AudioPlayer();
  final AudioPlayer refPlayer = AudioPlayer();

  late Directory _rootDir;
  late Directory _outputDir;
  late Directory _dataDir;
  late Directory _voicesDir;
  late Directory _tempDir;
  late OpenRouterService openRouter;

  bool initialized = false;
  String _apiKey = '';
  bool get isConfigured => _apiKey.isNotEmpty;
  AccountStatus? accountStatus;

  CatalogSnapshot catalog = const CatalogSnapshot(
    models: [],
    source: 'bundled',
    asOf: OpenRouterService.catalogDate,
  );
  bool refreshingModels = false;

  ReferenceVoice? lastReference;
  List<ProjectSummary> projectList = [];
  late NarrationProject project;
  NarrationPlan plan = const NarrationPlan(
    chunks: [],
    preview: null,
    requests: 0,
    estimatedSeconds: 0,
  );

  String saveState = 'New draft';
  JobState job = const JobState();
  bool _stopRequested = false;
  Timer? _saveDebounce;

  // Audio monitor state
  String trackTitle = 'Studio soundcheck';
  String trackMeta = 'Built-in demo recording';
  List<double> waveformPeaks = List<double>.filled(128, 0.2);
  Duration position = Duration.zero;
  Duration duration = const Duration(milliseconds: 8130);
  bool isPlaying = false;

  String? toastMessage;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _tempDir = await getTemporaryDirectory();
    _rootDir = Directory(p.join(docs.path, 'FishNarrator'));
    _outputDir = Directory(p.join(_rootDir.path, 'output'));
    _dataDir = Directory(p.join(_rootDir.path, 'data'));
    _voicesDir = Directory(p.join(_dataDir.path, 'voices'));

    for (final dir in [_rootDir, _outputDir, _dataDir, _voicesDir]) {
      await dir.create(recursive: true);
    }

    openRouter = OpenRouterService(
      cacheFile: File(p.join(_dataDir.path, 'catalog_cache.json')),
    );
    await openRouter.initCatalog();
    catalog = openRouter.snapshot();

    _apiKey = (await _secureStorage.read(key: _keyStorageName))?.trim() ?? '';
    await _loadLastReference();
    await _loadProjectList();

    if (projectList.isNotEmpty) {
      await openProject(projectList.first.id);
    } else {
      _createBlankDraft();
    }

    await _loadSoundcheck();
    _bindPlayerStreams();

    initialized = true;
    notifyListeners();

    // Refresh model catalog silently in background
    unawaited(refreshModels(force: false));
  }

  void _bindPlayerStreams() {
    player.positionStream.listen((pos) {
      position = pos;
      notifyListeners();
    });
    player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        duration = dur;
        notifyListeners();
      }
    });
    player.playerStateStream.listen((st) {
      isPlaying = st.playing && st.processingState != ProcessingState.completed;
      if (st.processingState == ProcessingState.completed) {
        player.seek(Duration.zero);
        player.pause();
      }
      notifyListeners();
    });
  }

  Future<void> _loadSoundcheck() async {
    try {
      final raw = await rootBundle.loadString('assets/soundcheck.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final peaks = (decoded['peaks'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          List<double>.filled(128, 0.2);
      waveformPeaks = peaks;
      trackTitle = 'Studio soundcheck';
      trackMeta = 'Built-in demo recording';
      await player.setAsset('assets/soundcheck.mp3');
    } catch (_) {}
  }

  Future<void> togglePlay() async {
    if (isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seekToFraction(double fraction) async {
    final targetMs = (duration.inMilliseconds * fraction.clamp(0.0, 1.0)).round();
    await player.seek(Duration(milliseconds: targetMs));
  }

  Future<void> playAudioFile(File file, {required String title, required String meta}) async {
    if (!await file.exists()) {
      showToast('Audio file not found.');
      return;
    }
    try {
      await player.stop();
      trackTitle = title;
      trackMeta = meta;
      if (file.path.toLowerCase().endsWith('.wav')) {
        waveformPeaks = await audioEngine.extractWaveformPeaks(file, count: 160);
      }
      await player.setFilePath(file.path);
      await player.play();
      notifyListeners();
    } catch (_) {
      showToast('Could not play this audio file.');
    }
  }

  void showToast(String message) {
    toastMessage = message;
    notifyListeners();
  }

  void clearToast() {
    toastMessage = null;
  }

  SpeechModel? get selectedModel {
    for (final m in catalog.models) {
      if (m.id == project.settings.model) return m;
    }
    return catalog.models.isNotEmpty ? catalog.models.first : null;
  }

  Directory projectDir(String id) => Directory(p.join(_outputDir.path, id));

  File? get referenceAudioFile {
    final id = project.settings.reference;
    if (id.isEmpty) return null;
    final f = File(p.join(_voicesDir.path, '$id.mp3'));
    return f.existsSync() ? f : null;
  }

  Future<void> refreshModels({bool force = true}) async {
    refreshingModels = true;
    notifyListeners();
    catalog = await openRouter.refreshCatalog(force: force);
    refreshingModels = false;
    recomputePlan();
    notifyListeners();
  }

  Future<AccountStatus> saveAndCheckKey(String rawKey) async {
    final trimmed = rawKey.trim();
    if (trimmed.isEmpty || trimmed.length > 512 || RegExp(r'\s').hasMatch(trimmed)) {
      throw const AppError('Enter a valid OpenRouter API key.');
    }
    final status = await openRouter.checkAccount(trimmed);
    await _secureStorage.write(key: _keyStorageName, value: trimmed);
    _apiKey = trimmed;
    accountStatus = status;
    notifyListeners();
    return status;
  }

  Future<AccountStatus> checkCurrentAccount() async {
    final status = await openRouter.checkAccount(_apiKey);
    accountStatus = status;
    notifyListeners();
    return status;
  }

  Future<void> disconnectKey() async {
    await _secureStorage.delete(key: _keyStorageName);
    _apiKey = '';
    accountStatus = null;
    notifyListeners();
  }

  Future<void> _loadLastReference() async {
    final file = File(p.join(_dataDir.path, 'last_voice.json'));
    if (await file.exists()) {
      try {
        lastReference = ReferenceVoice.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
  }

  void _createBlankDraft() {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = _randomId(12);
    var settings = const VoiceSettings();
    if (lastReference != null && lastReference!.id.isNotEmpty) {
      settings = settings.copyWith(
        reference: lastReference!.id,
        referenceText: lastReference!.text,
      );
    }
    project = NarrationProject(
      id: id,
      name: 'Untitled narration',
      script: '',
      settings: settings,
      created: now,
      updated: now,
    );
    saveState = 'New draft';
    recomputePlan();
  }

  void startNewProject() {
    if (job.isRunning) {
      showToast('Wait for the current job to finish first.');
      return;
    }
    _createBlankDraft();
    notifyListeners();
  }

  void updateScript(String text) {
    if (job.isRunning) return;
    project = project.copyWith(
      script: text,
      updated: DateTime.now().toUtc().toIso8601String(),
    );
    saveState = 'Saving…';
    recomputePlan();
    _scheduleSave();
    notifyListeners();
  }

  void updateProjectName(String name) {
    if (job.isRunning) return;
    final clean = name.trim().isEmpty ? 'Untitled narration' : name.trim();
    project = project.copyWith(
      name: clean.length > 100 ? clean.substring(0, 100) : clean,
      updated: DateTime.now().toUtc().toIso8601String(),
    );
    _scheduleSave(immediate: true);
    notifyListeners();
  }

  void updateSettings(VoiceSettings next) {
    if (job.isRunning) return;
    project = project.copyWith(
      settings: next,
      updated: DateTime.now().toUtc().toIso8601String(),
    );
    saveState = 'Saving…';
    recomputePlan();
    _scheduleSave();
    notifyListeners();
  }

  void loadSampleScript() {
    if (job.isRunning) return;
    updateScript(sampleScriptText);
  }

  Future<void> importTxtScript() async {
    if (job.isRunning) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (picked == null || picked.files.isEmpty || picked.files.first.path == null) {
      return;
    }
    final file = File(picked.files.first.path!);
    final content = await file.readAsString();
    final stem = p.basenameWithoutExtension(file.path);
    if (project.script.trim().isNotEmpty) {
      _createBlankDraft();
    }
    project = project.copyWith(
      name: stem.isEmpty ? 'Imported narration' : stem,
      script: content.length > 250000 ? content.substring(0, 250000) : content,
      updated: DateTime.now().toUtc().toIso8601String(),
    );
    recomputePlan();
    await persistProject();
    notifyListeners();
  }

  Future<void> pickReferenceVoice() async {
    if (job.isRunning) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (picked == null || picked.files.isEmpty || picked.files.first.path == null) {
      return;
    }
    final source = File(picked.files.first.path!);
    final size = await source.length();
    if (size <= 0 || size > 25 * 1024 * 1024) {
      showToast('Choose an audio recording smaller than 25 MB.');
      return;
    }
    try {
      showToast('Preparing reference clip (trimming to 30s)…');
      final prepared = await audioEngine.prepareReferenceVoice(source, _tempDir);
      final refId = sha256Digest(prepared);
      final dest = File(p.join(_voicesDir.path, '$refId.mp3'));
      await dest.writeAsBytes(prepared, flush: true);

      lastReference = ReferenceVoice(
        id: refId,
        name: p.basename(source.path),
        text: project.settings.referenceText,
      );
      await File(p.join(_dataDir.path, 'last_voice.json'))
          .writeAsString(jsonEncode(lastReference!.toJson()));

      updateSettings(project.settings.copyWith(
        voiceMode: 'clone',
        reference: refId,
      ));
      showToast('Reference voice ready.');
    } on AppError catch (e) {
      showToast(e.message);
    } catch (_) {
      showToast('Could not process this audio clip.');
    }
  }

  Future<void> previewReferenceClip() async {
    final file = referenceAudioFile;
    if (file == null) return;
    await playAudioFile(
      file,
      title: lastReference?.name ?? 'Reference voice',
      meta: '30s reference clip',
    );
  }

  void _scheduleSave({bool immediate = false}) {
    _saveDebounce?.cancel();
    if (immediate) {
      unawaited(persistProject());
    } else {
      _saveDebounce = Timer(const Duration(milliseconds: 500), () {
        unawaited(persistProject());
      });
    }
  }

  Future<void> persistProject() async {
    final dir = projectDir(project.id);
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'project.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
    );
    await File(p.join(dir.path, 'script.txt')).writeAsString(project.script);

    if (project.settings.voiceMode == 'clone' &&
        lastReference != null &&
        lastReference!.id == project.settings.reference) {
      lastReference = lastReference!.copyWith(text: project.settings.referenceText);
      await File(p.join(_dataDir.path, 'last_voice.json'))
          .writeAsString(jsonEncode(lastReference!.toJson()));
    }

    saveState = 'Saved';
    await _loadProjectList();
    notifyListeners();
  }

  Future<void> _loadProjectList() async {
    final items = <ProjectSummary>[];
    if (!await _outputDir.exists()) return;
    await for (final entity in _outputDir.list()) {
      if (entity is! Directory) continue;
      final projFile = File(p.join(entity.path, 'project.json'));
      if (!await projFile.exists()) continue;
      try {
        final json =
            jsonDecode(await projFile.readAsString()) as Map<String, dynamic>;
        final manifestFile = File(p.join(entity.path, 'manifest.json'));
        var ready = File(p.join(entity.path, 'narration.mp3')).existsSync();
        if (!ready && await manifestFile.exists()) {
          final m = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
          ready = m['render'] != null;
        }
        items.add(ProjectSummary(
          id: json['id']?.toString() ?? p.basename(entity.path),
          name: json['name']?.toString() ?? 'Untitled narration',
          updated: json['updated']?.toString() ?? '',
          words: wordCount(json['script']?.toString() ?? ''),
          ready: ready,
        ));
      } catch (_) {}
    }
    items.sort((a, b) => b.updated.compareTo(a.updated));
    projectList = items;
  }

  Future<void> openProject(String id) async {
    if (job.isRunning) {
      showToast('Wait for the current job to finish first.');
      return;
    }
    final dir = projectDir(id);
    final projFile = File(p.join(dir.path, 'project.json'));
    if (!await projFile.exists()) return;

    final json = jsonDecode(await projFile.readAsString()) as Map<String, dynamic>;
    RenderResult? render;
    final manifestFile = File(p.join(dir.path, 'manifest.json'));
    if (await manifestFile.exists()) {
      try {
        final m = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        if (m['render'] is Map) {
          render = RenderResult.fromJson((m['render'] as Map).cast<String, dynamic>());
        }
      } catch (_) {}
    }

    project = NarrationProject.fromJson(json, render: render);
    saveState = 'Saved';
    recomputePlan();

    if (render != null) {
      final wav = File(p.join(dir.path, render.wav));
      if (await wav.exists()) {
        await playAudioFile(
          wav,
          title: project.name,
          meta: 'Final narration mix',
        );
        await player.pause();
      }
    }
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    if (job.isRunning && project.id == id) {
      showToast('Stop the running job before deleting this project.');
      return;
    }
    final dir = projectDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await _loadProjectList();
    if (project.id == id) {
      if (projectList.isNotEmpty) {
        await openProject(projectList.first.id);
      } else {
        _createBlankDraft();
      }
    }
    notifyListeners();
  }

  void recomputePlan() {
    final model = selectedModel ??
        SpeechModel.describe({'id': project.settings.model});
    plan = buildNarrationPlan(
      script: project.script,
      settings: project.settings,
      model: model,
      projectDir: projectDir(project.id),
    );
  }

  void stopJob() {
    if (!job.isRunning) return;
    _stopRequested = true;
    _logJob('Stopping after the current request. Finished sections will be saved.');
  }

  void _logJob(String msg) {
    final nextLogs = [...job.logs, msg];
    job = job.copyWith(
      message: msg,
      logs: nextLogs.length > 100 ? nextLogs.sublist(nextLogs.length - 100) : nextLogs,
    );
    notifyListeners();
  }

  Future<void> runJob({String mode = 'generate', int? redoIndex}) async {
    if (job.isRunning) return;
    await persistProject();
    recomputePlan();

    if (plan.chunks.isEmpty) {
      showToast('Write or import your script first.');
      return;
    }
    if (mode == 'redo' && (redoIndex == null || redoIndex < 1 || redoIndex > plan.chunks.length)) {
      showToast('Choose a section to redo.');
      return;
    }

    _stopRequested = false;
    final dir = projectDir(project.id);
    final settings = project.settings;
    final chunks = mode == 'preview'
        ? [plan.preview!]
        : List<ScriptChunk>.from(plan.chunks);

    job = JobState(
      mode: mode,
      status: 'running',
      phase: 'preparing',
      message: 'Preparing narration…',
      done: 0,
      total: chunks.length,
      logs: const ['Preparing narration…'],
    );
    notifyListeners();

    var finalStatus = 'completed';
    try {
      var model = await openRouter.getModel(settings.model, forPlan: true);
      Uint8List? refBytes;
      var verified = false;

      for (var i = 0; i < chunks.length; i++) {
        if (_stopRequested) {
          throw const StoppedError(
            'Stopped. Finished sections are saved. Generate to resume.',
          );
        }
        final chunk = chunks[i];
        final dest = File(p.join(dir.path, chunk.path));
        var mustGenerate = !await dest.exists() ||
            (mode == 'redo' && redoIndex == chunk.index);

        if (!mustGenerate) {
          final dur = await audioEngine.wavDuration(dest);
          if (dur <= 0) mustGenerate = true;
        }

        job = job.copyWith(current: chunk.index);
        notifyListeners();

        if (mustGenerate) {
          if (mode == 'redo' && chunk.index != redoIndex) {
            chunks[i] = chunk.copyWith(cached: false);
            continue;
          }
          if (_apiKey.isEmpty) {
            throw const AppError(
              'Connect your OpenRouter key in Settings to generate speech.',
            );
          }
          if (!verified) {
            _logJob('Checking model availability…');
            model = await openRouter.getModel(settings.model, live: true);
            catalog = openRouter.snapshot();
            if (settings.voiceMode == 'clone') {
              if (!model.cloning) {
                throw const AppError(
                  'This model does not advertise reference cloning. Select a preset voice.',
                );
              }
              final refFile = referenceAudioFile;
              if (refFile == null) {
                throw const AppError(
                  'Upload a reference recording before using your own voice.',
                );
              }
              refBytes = await refFile.readAsBytes();
            } else if (model.voices.isNotEmpty &&
                settings.voice.isNotEmpty &&
                !model.voices.contains(settings.voice)) {
              throw const AppError(
                'The voice catalog changed. Refresh models and select an available voice.',
              );
            }
            verified = true;
          }

          job = job.copyWith(phase: 'generating');
          _logJob(
            'Generating section ${chunk.index} of ${chunks.length} · ${chunk.words} words',
          );

          final audio = await openRouter.synthesize(
            key: _apiKey,
            model: model,
            text: chunk.text,
            settings: settings,
            referenceBytes: refBytes,
            isStopped: () => _stopRequested,
            onLog: _logJob,
          );

          await audioEngine.normalizeToWav(
            audioBytes: audio.bytes,
            contentType: audio.contentType,
            model: model,
            destination: dest,
            tempDir: _tempDir,
            previewSpeed: mode == 'preview' ? settings.speed : null,
            previewNormalize: mode == 'preview' && settings.normalize,
          );

          final dur = await audioEngine.wavDuration(dest);
          final warn = dur < (chunk.words / 6.0)
              ? 'This section seems short. Listen and redo if speech is missing.'
              : '';
          chunks[i] = chunk.copyWith(
            cached: true,
            duration: double.parse(dur.toStringAsFixed(3)),
            warning: warn,
          );
          _logJob('Section ${chunk.index} saved.');
        } else {
          final dur = await audioEngine.wavDuration(dest);
          chunks[i] = chunk.copyWith(
            cached: true,
            duration: double.parse(dur.toStringAsFixed(3)),
          );
          _logJob('Reused saved section ${chunk.index}.');
        }

        job = job.copyWith(done: job.done + 1);
        if (mode != 'preview') {
          await _writeManifest(dir, chunks, project.render);
        }
        notifyListeners();
      }

      if (mode == 'preview') {
        final previewFile = File(p.join(dir.path, chunks.first.path));
        _logJob('Voice preview is ready.');
        await playAudioFile(
          previewFile,
          title: '${project.name} (Preview)',
          meta: 'Opening ${chunks.first.words} words',
        );
      } else if (!chunks.every((c) => c.cached)) {
        await _writeManifest(dir, chunks, project.render);
        _logJob(
          'Section $redoIndex is ready. Generate narration to finish remaining sections.',
        );
      } else {
        if (_stopRequested) {
          throw const StoppedError(
            'Stopped. Finished sections are saved. Generate to export.',
          );
        }
        job = job.copyWith(phase: 'exporting');
        _logJob('Preparing MP3, WAV and section bundle…');

        final renderId = _randomId(12);
        final relative = 'renders/$renderId';
        final exportDir = Directory(p.join(dir.path, relative));

        final totalSeconds = await audioEngine.joinAndExport(
          chunkFiles: chunks.map((c) => File(p.join(dir.path, c.path))).toList(),
          exportDir: exportDir,
          tempDir: _tempDir,
          pauseSeconds: settings.pause,
          speed: settings.speed,
          normalize: settings.normalize,
        );

        await File(p.join(exportDir.path, 'script.txt'))
            .writeAsString(project.script);
        await File(p.join(exportDir.path, 'settings.json')).writeAsString(
          const JsonEncoder.withIndent('  ').convert(settings.toJson()),
        );
        await audioEngine.createBundle(
          exportDir: exportDir,
          projectDir: dir,
          chunks: chunks,
        );

        // Publish latest narration.mp3 and narration.wav at project root
        await File(p.join(exportDir.path, 'narration.mp3'))
            .copy(p.join(dir.path, 'narration.mp3'));
        await File(p.join(exportDir.path, 'narration.wav'))
            .copy(p.join(dir.path, 'narration.wav'));

        final render = RenderResult(
          signature: sha256Digest({
            'script': project.script,
            'settings': settings.toJson(),
          }),
          audioRevision: sha256Digest(chunks.map((c) => c.signature).toList()),
          created: DateTime.now().toUtc().toIso8601String(),
          duration: double.parse(totalSeconds.toStringAsFixed(2)),
          mp3: '$relative/narration.mp3',
          wav: '$relative/narration.wav',
          bundle: '$relative/narration_bundle.zip',
        );

        project = project.copyWith(render: render);
        await _writeManifest(dir, chunks, render);
        await _loadProjectList();
        _logJob('Your narration is ready.');

        await playAudioFile(
          File(p.join(dir.path, render.wav)),
          title: project.name,
          meta: 'Final mix · ${_formatSeconds(totalSeconds)}',
        );
      }
    } on StoppedError catch (e) {
      finalStatus = 'stopped';
      _logJob(e.message);
    } on AppError catch (e) {
      finalStatus = 'error';
      _logJob(e.message);
    } catch (e) {
      finalStatus = 'error';
      _logJob('This job could not finish. Saved sections are kept. ($e)');
    } finally {
      job = job.copyWith(phase: 'finished', status: finalStatus);
      recomputePlan();
      notifyListeners();
    }
  }

  Future<void> playSection(ScriptChunk chunk) async {
    final f = File(p.join(projectDir(project.id).path, chunk.path));
    await playAudioFile(
      f,
      title: 'Section ${chunk.index}',
      meta: '${chunk.words} words',
    );
  }

  Future<void> playFinalMix() async {
    final render = project.render;
    if (render == null) return;
    final wav = File(p.join(projectDir(project.id).path, render.wav));
    await playAudioFile(
      wav,
      title: project.name,
      meta: 'Final narration mix',
    );
  }

  Future<void> shareExport(String kind) async {
    final render = project.render;
    if (render == null) return;
    final rel = switch (kind) {
      'mp3' => render.mp3,
      'wav' => render.wav,
      'bundle' => render.bundle,
      _ => render.mp3,
    };
    final file = File(p.join(projectDir(project.id).path, rel));
    if (!await file.exists()) {
      showToast('Export file not found.');
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '${project.name} ($kind)',
    );
  }

  Future<void> _writeManifest(
    Directory dir,
    List<ScriptChunk> chunks,
    RenderResult? render,
  ) async {
    final manifest = <String, dynamic>{
      'chunks': chunks.map((c) => c.toJson()).toList(),
      if (render != null) 'render': render.toJson(),
    };
    await File(p.join(dir.path, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
  }

  String _randomId(int len) {
    const chars = 'abcdef0123456789';
    final rng = Random.secure();
    return List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _formatSeconds(double secs) {
    final total = secs.round();
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    player.dispose();
    refPlayer.dispose();
    super.dispose();
  }
}
