class AppError implements Exception {
  final String message;
  const AppError(this.message);

  @override
  String toString() => message;
}

class StoppedError extends AppError {
  const StoppedError(super.message);
}

class SpeechModel {
  final String id;
  final String name;
  final List<String> voices;
  final String? expires;
  final String description;
  final String format; // 'mp3' or 'pcm'
  final int? sampleRate;
  final int maxChars;
  final bool cloning;
  final bool transcript;
  final bool instructions;
  final List<String> tags;
  final bool available;

  const SpeechModel({
    required this.id,
    required this.name,
    required this.voices,
    required this.expires,
    required this.description,
    required this.format,
    required this.sampleRate,
    required this.maxChars,
    required this.cloning,
    required this.transcript,
    required this.instructions,
    required this.tags,
    required this.available,
  });

  static const String defaultModelId = 'fish-audio/s2.1-pro-free:free';
  static const String heygenModelId = 'heygen/heygen-voice-1-turbo:free';

  factory SpeechModel.describe(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    final name = raw['name']?.toString() ?? id;
    final rawVoices = (raw['supported_voices'] as List?)
            ?.whereType<String>()
            .toList() ??
        <String>[];
    final expires = raw['expiration_date']?.toString();
    final description = raw['description']?.toString() ?? '';

    var format = 'pcm';
    int? sampleRate;
    var maxChars = 3000;
    var cloning = false;
    var transcript = false;
    var instructions = false;
    var tags = <String>[];
    var voices = List<String>.from(rawVoices);

    if (id == defaultModelId) {
      format = 'mp3';
      sampleRate = 44100;
      cloning = true;
      transcript = true;
      instructions = true;
      tags = const ['[whispering]', '[excited]', '[sad]', '[sigh]'];
    } else if (id == heygenModelId) {
      sampleRate = 44100;
      maxChars = 5000;
      cloning = true;
      tags = const ['[whispers]', '[sad]', '[slowly]', '[laughs]', '[sighs]'];
    } else {
      final params = (raw['speech_params'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final formats = ((params['response_format'] as Map?)?['values'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      if (formats.contains('mp3')) {
        format = 'mp3';
      }
      instructions = params.containsKey('instructions');
      cloning = raw['can_clone'] == true;
      if (voices.isEmpty) {
        voices = ((params['voice'] as Map?)?['values'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[];
      }
    }

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final available =
        expires == null || expires.isEmpty || expires.compareTo(today) >= 0;

    return SpeechModel(
      id: id,
      name: name,
      voices: voices,
      expires: expires,
      description: description,
      format: format,
      sampleRate: sampleRate,
      maxChars: maxChars,
      cloning: cloning,
      transcript: transcript,
      instructions: instructions,
      tags: tags,
      available: available,
    );
  }
}

class CatalogSnapshot {
  final List<SpeechModel> models;
  final String source; // 'live', 'cached', 'bundled'
  final String asOf;
  final String error;

  const CatalogSnapshot({
    required this.models,
    required this.source,
    required this.asOf,
    this.error = '',
  });
}

class ReferenceVoice {
  final String id;
  final String name;
  final String text;

  const ReferenceVoice({
    required this.id,
    required this.name,
    this.text = '',
  });

  ReferenceVoice copyWith({String? id, String? name, String? text}) {
    return ReferenceVoice(
      id: id ?? this.id,
      name: name ?? this.name,
      text: text ?? this.text,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'text': text};

  factory ReferenceVoice.fromJson(Map<String, dynamic> json) {
    return ReferenceVoice(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Reference recording',
      text: json['text']?.toString() ?? '',
    );
  }
}

class VoiceSettings {
  final String model;
  final String voice;
  final String voiceMode; // 'default' or 'clone'
  final String reference;
  final String referenceText;
  final String instructions;
  final int chunkWords;
  final double speed;
  final double pause;
  final bool normalize;

  const VoiceSettings({
    this.model = SpeechModel.defaultModelId,
    this.voice = '',
    this.voiceMode = 'default',
    this.reference = '',
    this.referenceText = '',
    this.instructions = '',
    this.chunkWords = 280,
    this.speed = 1.0,
    this.pause = 0.4,
    this.normalize = true,
  });

  VoiceSettings copyWith({
    String? model,
    String? voice,
    String? voiceMode,
    String? reference,
    String? referenceText,
    String? instructions,
    int? chunkWords,
    double? speed,
    double? pause,
    bool? normalize,
  }) {
    return VoiceSettings(
      model: model ?? this.model,
      voice: voice ?? this.voice,
      voiceMode: voiceMode ?? this.voiceMode,
      reference: reference ?? this.reference,
      referenceText: referenceText ?? this.referenceText,
      instructions: instructions ?? this.instructions,
      chunkWords: chunkWords ?? this.chunkWords,
      speed: speed ?? this.speed,
      pause: pause ?? this.pause,
      normalize: normalize ?? this.normalize,
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'voice': voice,
        'voice_mode': voiceMode,
        'reference': reference,
        'reference_text': referenceText,
        'instructions': instructions,
        'chunk_words': chunkWords,
        'speed': speed,
        'pause': pause,
        'normalize': normalize,
      };

  factory VoiceSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const VoiceSettings();
    return VoiceSettings(
      model: json['model']?.toString() ?? SpeechModel.defaultModelId,
      voice: json['voice']?.toString() ?? '',
      voiceMode: json['voice_mode']?.toString() == 'clone' ? 'clone' : 'default',
      reference: json['reference']?.toString() ?? '',
      referenceText: json['reference_text']?.toString() ?? '',
      instructions: json['instructions']?.toString() ?? '',
      chunkWords: ((json['chunk_words'] as num?)?.toInt() ?? 280).clamp(50, 400),
      speed: ((json['speed'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.0),
      pause: ((json['pause'] as num?)?.toDouble() ?? 0.4).clamp(0.0, 2.0),
      normalize: json['normalize'] != false,
    );
  }
}

class ScriptChunk {
  final int index;
  final String text;
  final int words;
  final int chars;
  final String signature;
  final String path;
  final bool cached;
  final double? duration;
  final String warning;

  const ScriptChunk({
    required this.index,
    required this.text,
    required this.words,
    required this.chars,
    required this.signature,
    required this.path,
    required this.cached,
    this.duration,
    this.warning = '',
  });

  ScriptChunk copyWith({
    bool? cached,
    double? duration,
    String? warning,
  }) {
    return ScriptChunk(
      index: index,
      text: text,
      words: words,
      chars: chars,
      signature: signature,
      path: path,
      cached: cached ?? this.cached,
      duration: duration ?? this.duration,
      warning: warning ?? this.warning,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'text': text,
        'words': words,
        'chars': chars,
        'signature': signature,
        'path': path,
        'cached': cached,
        if (duration != null) 'duration': duration,
        if (warning.isNotEmpty) 'warning': warning,
      };

  factory ScriptChunk.fromJson(Map<String, dynamic> json) {
    return ScriptChunk(
      index: (json['index'] as num?)?.toInt() ?? 1,
      text: json['text']?.toString() ?? '',
      words: (json['words'] as num?)?.toInt() ?? 0,
      chars: (json['chars'] as num?)?.toInt() ?? 0,
      signature: json['signature']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      cached: json['cached'] == true,
      duration: (json['duration'] as num?)?.toDouble(),
      warning: json['warning']?.toString() ?? '',
    );
  }
}

class NarrationPlan {
  final List<ScriptChunk> chunks;
  final ScriptChunk? preview;
  final int requests;
  final int estimatedSeconds;

  const NarrationPlan({
    required this.chunks,
    required this.preview,
    required this.requests,
    required this.estimatedSeconds,
  });
}

class RenderResult {
  final String signature;
  final String audioRevision;
  final String created;
  final double duration;
  final String mp3;
  final String wav;
  final String bundle;

  const RenderResult({
    required this.signature,
    required this.audioRevision,
    required this.created,
    required this.duration,
    required this.mp3,
    required this.wav,
    required this.bundle,
  });

  Map<String, dynamic> toJson() => {
        'signature': signature,
        'audio_revision': audioRevision,
        'created': created,
        'duration': duration,
        'mp3': mp3,
        'wav': wav,
        'bundle': bundle,
      };

  factory RenderResult.fromJson(Map<String, dynamic> json) {
    return RenderResult(
      signature: json['signature']?.toString() ?? '',
      audioRevision: json['audio_revision']?.toString() ?? '',
      created: json['created']?.toString() ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      mp3: json['mp3']?.toString() ?? '',
      wav: json['wav']?.toString() ?? '',
      bundle: json['bundle']?.toString() ?? '',
    );
  }
}

class NarrationProject {
  final String id;
  final String name;
  final String script;
  final VoiceSettings settings;
  final String created;
  final String updated;
  final RenderResult? render;

  const NarrationProject({
    required this.id,
    required this.name,
    required this.script,
    required this.settings,
    required this.created,
    required this.updated,
    this.render,
  });

  NarrationProject copyWith({
    String? name,
    String? script,
    VoiceSettings? settings,
    String? updated,
    RenderResult? render,
    bool clearRender = false,
  }) {
    return NarrationProject(
      id: id,
      name: name ?? this.name,
      script: script ?? this.script,
      settings: settings ?? this.settings,
      created: created,
      updated: updated ?? this.updated,
      render: clearRender ? null : (render ?? this.render),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'script': script,
        'settings': settings.toJson(),
        'created': created,
        'updated': updated,
      };

  factory NarrationProject.fromJson(
    Map<String, dynamic> json, {
    RenderResult? render,
  }) {
    return NarrationProject(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled narration',
      script: json['script']?.toString() ?? '',
      settings: VoiceSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, dynamic>(),
      ),
      created: json['created']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      updated: json['updated']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      render: render,
    );
  }
}

class ProjectSummary {
  final String id;
  final String name;
  final String updated;
  final int words;
  final bool ready;

  const ProjectSummary({
    required this.id,
    required this.name,
    required this.updated,
    required this.words,
    required this.ready,
  });
}

class JobState {
  final String mode; // 'generate', 'preview', 'redo'
  final String status; // 'idle', 'running', 'completed', 'stopped', 'error'
  final String phase;
  final String message;
  final int done;
  final int total;
  final List<String> logs;
  final int? current;

  const JobState({
    this.mode = 'generate',
    this.status = 'idle',
    this.phase = '',
    this.message = '',
    this.done = 0,
    this.total = 1,
    this.logs = const [],
    this.current,
  });

  bool get isRunning => status == 'running';

  JobState copyWith({
    String? mode,
    String? status,
    String? phase,
    String? message,
    int? done,
    int? total,
    List<String>? logs,
    int? current,
  }) {
    return JobState(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      phase: phase ?? this.phase,
      message: message ?? this.message,
      done: done ?? this.done,
      total: total ?? this.total,
      logs: logs ?? this.logs,
      current: current ?? this.current,
    );
  }
}

class AccountStatus {
  final bool configured;
  final bool valid;
  final Map<String, dynamic>? freeRequests;
  final String note;

  const AccountStatus({
    required this.configured,
    this.valid = false,
    this.freeRequests,
    this.note = '',
  });
}
