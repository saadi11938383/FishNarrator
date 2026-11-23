import 'dart:math';

import 'package:flutter/material.dart';

import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class AudioMonitorCard extends StatelessWidget {
  final StudioController controller;

  const AudioMonitorCard({super.key, required this.controller});

  String _fmt(Duration d) {
    final total = d.inSeconds.clamp(0, 359999);
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = max(1, controller.duration.inMilliseconds);
    final progress = (controller.position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final render = controller.project.render;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                StudioColors.monitorStart,
                StudioColors.monitorMid,
                StudioColors.monitorEnd,
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: StudioColors.monitorBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.headphones, size: 15, color: StudioColors.lime),
                      SizedBox(width: 6),
                      Text(
                        'AUDIO MONITOR',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFC1CFC3),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${_fmt(controller.position)} / ${_fmt(controller.duration)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFFE1EDDF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  InkWell(
                    onTap: controller.togglePlay,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: StudioColors.lime,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        controller.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: const Color(0xFF193022),
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.trackTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF5FAEE),
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          controller.trackMeta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB8C9BA),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      controller.seekToFraction(
                        d.localPosition.dx / max(1, constraints.maxWidth),
                      );
                    },
                    onHorizontalDragUpdate: (d) {
                      controller.seekToFraction(
                        d.localPosition.dx / max(1, constraints.maxWidth),
                      );
                    },
                    child: SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          peaks: controller.waveformPeaks,
                          progress: progress,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        if (render != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: controller.playFinalMix,
                icon: const Icon(Icons.headphones, size: 17),
                label: const Text('Listen to final mix'),
                style: TextButton.styleFrom(
                  foregroundColor: StudioColors.forest,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  _ExportChip(
                    label: 'MP3',
                    icon: Icons.share,
                    onTap: () => controller.shareExport('mp3'),
                  ),
                  _ExportChip(
                    label: 'WAV',
                    icon: Icons.share,
                    onTap: () => controller.shareExport('wav'),
                  ),
                  _ExportChip(
                    label: 'Bundle',
                    icon: Icons.folder_zip_outlined,
                    onTap: () => controller.shareExport('bundle'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ExportChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ExportChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: StudioColors.forest,
        side: const BorderSide(color: StudioColors.line),
        backgroundColor: StudioColors.paper,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double progress;

  const _WaveformPainter({required this.peaks, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final barCount = min(peaks.length, max(32, (size.width / 4.2).floor()));
    final step = size.width / barCount;
    final barWidth = max(1.8, step * 0.58);
    final midY = size.height / 2;

    final playedPaint = Paint()
      ..color = StudioColors.lime
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final unplayedPaint = Paint()
      ..color = const Color(0xFF4A6858)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < barCount; i++) {
      final srcIndex = (i * peaks.length / barCount).floor().clamp(0, peaks.length - 1);
      final amp = peaks[srcIndex].clamp(0.08, 1.0);
      final halfH = max(2.5, amp * (size.height * 0.44));
      final x = i * step + step / 2;
      final frac = i / barCount;
      canvas.drawLine(
        Offset(x, midY - halfH),
        Offset(x, midY + halfH),
        frac <= progress ? playedPaint : unplayedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.peaks != peaks;
  }
}
