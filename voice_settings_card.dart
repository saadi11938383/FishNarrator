import 'package:flutter/material.dart';

import '../models/studio_models.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class VoiceSettingsCard extends StatefulWidget {
  final StudioController controller;

  const VoiceSettingsCard({super.key, required this.controller});

  @override
  State<VoiceSettingsCard> createState() => _VoiceSettingsCardState();
}

class _VoiceSettingsCardState extends State<VoiceSettingsCard> {
  final TextEditingController _transcriptCtrl = TextEditingController();
  final TextEditingController _directionsCtrl = TextEditingController();
  final TextEditingController _customVoiceCtrl = TextEditingController();
  String _lastProjectId = '';

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant VoiceSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  void _syncControllers() {
    final p = widget.controller.project;
    if (_lastProjectId != p.id) {
      _lastProjectId = p.id;
      _transcriptCtrl.text = p.settings.referenceText;
      _directionsCtrl.text = p.settings.instructions;
      _customVoiceCtrl.text = p.settings.voice;
    }
  }

  @override
  void dispose() {
    _transcriptCtrl.dispose();
    _directionsCtrl.dispose();
    _customVoiceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final settings = ctrl.project.settings;
    final models = ctrl.catalog.models;
    final selectedModel = ctrl.selectedModel;
    final busy = ctrl.job.isRunning;

    final voiceOptions = <DropdownMenuItem<String>>[];
    if (selectedModel != null && selectedModel.voices.isNotEmpty) {
      for (final v in selectedModel.voices) {
        voiceOptions.add(DropdownMenuItem(value: 'preset:$v', child: Text(v)));
      }
    } else {
      voiceOptions.add(
        const DropdownMenuItem(value: 'preset:', child: Text('Provider default')),
      );
    }
    if (selectedModel == null || selectedModel.cloning) {
      voiceOptions.add(
        const DropdownMenuItem(value: 'clone', child: Text('My reference voice')),
      );
    }

    var currentVoiceValue = settings.voiceMode == 'clone'
        ? 'clone'
        : 'preset:${settings.voice}';
    if (!voiceOptions.any((item) => item.value == currentVoiceValue)) {
      currentVoiceValue = voiceOptions.first.value!;
    }

    final reqCount = ctrl.plan.requests;
    final totalChunks = ctrl.plan.chunks.length;
    final requestSummary = totalChunks == 0
        ? 'Add a script to estimate requests.'
        : reqCount == 0
            ? 'All $totalChunks section(s) cached · 0 new requests needed.'
            : '$reqCount request(s) for $totalChunks section(s) · Preview uses 1 request.';

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: StudioColors.tileBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune, size: 18, color: StudioColors.forest),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Voice settings',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh free models',
                  onPressed: ctrl.refreshingModels
                      ? null
                      : () => ctrl.refreshModels(force: true),
                  icon: ctrl.refreshingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Speech model',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: StudioColors.freeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.circle, size: 6, color: Color(0xFF619648)),
                          SizedBox(width: 4),
                          Text(
                            'Free',
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: StudioColors.freeInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: models.any((m) => m.id == settings.model)
                      ? settings.model
                      : (models.isNotEmpty ? models.first.id : null),
                  isExpanded: true,
                  items: models
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              m.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (val) {
                          if (val == null) return;
                          final picked = models.firstWhere((m) => m.id == val);
                          ctrl.updateSettings(settings.copyWith(
                            model: val,
                            voice: picked.voices.isNotEmpty ? picked.voices.first : '',
                            voiceMode: (settings.voiceMode == 'clone' && picked.cloning)
                                ? 'clone'
                                : 'default',
                          ));
                        },
                ),
                if (selectedModel != null && selectedModel.expires != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Free listing expires ${selectedModel.expires}.',
                    style: const TextStyle(fontSize: 11, color: StudioColors.muted),
                  ),
                ],
                if (ctrl.catalog.error.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    ctrl.catalog.error,
                    style: const TextStyle(fontSize: 11, color: StudioColors.errorInk),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  'Voice',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: currentVoiceValue,
                  isExpanded: true,
                  items: voiceOptions,
                  onChanged: busy
                      ? null
                      : (val) {
                          if (val == null) return;
                          if (val == 'clone') {
                            ctrl.updateSettings(settings.copyWith(
                              voiceMode: 'clone',
                              reference: settings.reference.isNotEmpty
                                  ? settings.reference
                                  : (ctrl.lastReference?.id ?? ''),
                            ));
                          } else {
                            ctrl.updateSettings(settings.copyWith(
                              voiceMode: 'default',
                              voice: val.substring('preset:'.length),
                            ));
                          }
                        },
                ),
                if (settings.voiceMode == 'clone') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.only(left: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Color(0xFFCADAaf), width: 2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: busy ? null : ctrl.pickReferenceVoice,
                              icon: const Icon(Icons.mic, size: 16),
                              label: const Text('Choose recording'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: StudioColors.ink,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            if (ctrl.referenceAudioFile != null)
                              IconButton(
                                tooltip: 'Play reference clip',
                                onPressed: ctrl.previewReferenceClip,
                                icon: const Icon(Icons.play_circle_outline),
                                color: StudioColors.forest,
                              ),
                            Text(
                              ctrl.lastReference?.name ?? 'No clip selected',
                              style: const TextStyle(
                                fontSize: 11,
                                color: StudioColors.muted,
                              ),
                            ),
                          ],
                        ),
                        if (selectedModel == null || selectedModel.transcript) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Reference transcript (optional)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _transcriptCtrl,
                            enabled: !busy,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              hintText: 'Words spoken in the clip',
                            ),
                            onChanged: (v) => ctrl.updateSettings(
                              settings.copyWith(referenceText: v),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        const Text(
                          'Use 10–30 seconds of clear speech. First 30 seconds are sent with each request.',
                          style: TextStyle(fontSize: 11, color: StudioColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Row(
                    children: [
                      const Icon(Icons.tune, size: 16, color: StudioColors.muted),
                      const SizedBox(width: 6),
                      const Text(
                        'Mix settings',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '${settings.speed.toStringAsFixed(2)}×',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: StudioColors.muted,
                        ),
                      ),
                    ],
                  ),
                  children: [
                    _SliderRow(
                      label: 'Playback speed',
                      valueText: '${settings.speed.toStringAsFixed(2)}×',
                      value: settings.speed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 30,
                      enabled: !busy,
                      onChanged: (v) => ctrl.updateSettings(
                        settings.copyWith(speed: double.parse(v.toStringAsFixed(2))),
                      ),
                    ),
                    _SliderRow(
                      label: 'Pause between sections',
                      valueText: '${settings.pause.toStringAsFixed(2)} s',
                      value: settings.pause,
                      min: 0.0,
                      max: 2.0,
                      divisions: 40,
                      enabled: !busy,
                      onChanged: (v) => ctrl.updateSettings(
                        settings.copyWith(pause: double.parse(v.toStringAsFixed(2))),
                      ),
                    ),
                    _SliderRow(
                      label: 'Words per section',
                      valueText: '${settings.chunkWords}',
                      value: settings.chunkWords.toDouble(),
                      min: 50,
                      max: 400,
                      divisions: 35,
                      enabled: !busy,
                      onChanged: (v) => ctrl.updateSettings(
                        settings.copyWith(chunkWords: v.round()),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: settings.normalize,
                      onChanged: busy
                          ? null
                          : (v) => ctrl.updateSettings(
                                settings.copyWith(normalize: v ?? true),
                              ),
                      title: const Text(
                        'Balance output loudness',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    if (selectedModel == null || selectedModel.instructions) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Delivery directions (optional)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _directionsCtrl,
                        enabled: !busy,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Warm, close to the microphone…',
                        ),
                        onChanged: (v) => ctrl.updateSettings(
                          settings.copyWith(instructions: v),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (ctrl.job.status != 'idle') _JobStatusBox(controller: ctrl),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFBF8),
              border: Border(top: BorderSide(color: StudioColors.line)),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => ctrl.runJob(mode: 'preview'),
                      icon: const Icon(Icons.headphones, size: 17),
                      label: const Text('Preview'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: StudioColors.ink,
                        backgroundColor: StudioColors.paper,
                        side: const BorderSide(color: Color(0xFFD2DBD0)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : () => ctrl.runJob(mode: 'generate'),
                        icon: const Icon(Icons.graphic_eq, size: 18),
                        label: const Text('Generate narration'),
                        style: FilledButton.styleFrom(
                          backgroundColor: StudioColors.lime,
                          foregroundColor: StudioColors.limeInk,
                          side: const BorderSide(color: StudioColors.limeBorder),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          textStyle: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  requestSummary,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: StudioColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(
              valueText,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: StudioColors.muted,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

class _JobStatusBox extends StatelessWidget {
  final StudioController controller;

  const _JobStatusBox({required this.controller});

  @override
  Widget build(BuildContext context) {
    final job = controller.job;
    final isError = job.status == 'error';
    final progress = job.total > 0 ? (job.done / job.total).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? StudioColors.errorBg : const Color(0xFFEEF6E9),
        border: Border.all(
          color: isError ? StudioColors.errorBorder : const Color(0xFFCDDCC6),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.isRunning
                      ? 'Working (${job.done}/${job.total})'
                      : job.status == 'completed'
                          ? 'Completed'
                          : job.status == 'stopped'
                              ? 'Stopped'
                              : 'Issue encountered',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              if (job.isRunning)
                TextButton(
                  onPressed: controller.stopJob,
                  style: TextButton.styleFrom(
                    foregroundColor: StudioColors.forest,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Stop after section'),
                ),
            ],
          ),
          Text(
            job.message,
            style: TextStyle(
              fontSize: 12,
              color: isError ? StudioColors.errorInk : StudioColors.muted,
            ),
          ),
          if (job.isRunning) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.done == 0 ? null : progress,
              color: StudioColors.forestAccent,
              backgroundColor: StudioColors.line,
            ),
          ],
        ],
      ),
    );
  }
}
