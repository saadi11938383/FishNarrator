import 'package:flutter/material.dart';

import '../services/script_splitter.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class ScriptEditorCard extends StatefulWidget {
  final StudioController controller;

  const ScriptEditorCard({super.key, required this.controller});

  @override
  State<ScriptEditorCard> createState() => _ScriptEditorCardState();
}

class _ScriptEditorCardState extends State<ScriptEditorCard> {
  final TextEditingController _textController = TextEditingController();
  int _tabIndex = 0; // 0 = Write, 1 = Sections
  String _lastProjectId = '';

  @override
  void initState() {
    super.initState();
    _syncFromProject();
  }

  @override
  void didUpdateWidget(covariant ScriptEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromProject();
  }

  void _syncFromProject() {
    final p = widget.controller.project;
    if (_lastProjectId != p.id || _textController.text != p.script) {
      _lastProjectId = p.id;
      final selection = _textController.selection;
      _textController.text = p.script;
      if (selection.isValid && selection.end <= p.script.length) {
        _textController.selection = selection;
      }
    }
  }

  void _insertTag(String tag) {
    final text = _textController.text;
    final sel = _textController.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final prefix = (start > 0 && !text[start - 1].trim().isEmpty) ? ' ' : '';
    final insert = '$prefix$tag ';
    final updated = text.replaceRange(start, end, insert);
    _textController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    widget.controller.updateScript(updated);
  }

  String _fmtSeconds(int secs) {
    final m = secs ~/ 60;
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final words = wordCount(ctrl.project.script);
    final chunks = ctrl.plan.chunks;
    final tags = ctrl.selectedModel?.tags ?? const <String>[];
    final busy = ctrl.job.isRunning;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: StudioColors.tileBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.notes, size: 18, color: StudioColors.forest),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Script editor',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : ctrl.importTxtScript,
                  icon: const Icon(Icons.upload_file, size: 15),
                  label: const Text('Import .txt'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: StudioColors.ink,
                    side: const BorderSide(color: Color(0xFFD2DBD0)),
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _TabButton(
                  label: 'Write',
                  selected: _tabIndex == 0,
                  onTap: () => setState(() => _tabIndex = 0),
                ),
                const SizedBox(width: 18),
                _TabButton(
                  label: 'Sections',
                  badge: '${chunks.length}',
                  selected: _tabIndex == 1,
                  onTap: () => setState(() => _tabIndex = 1),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_tabIndex == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _textController,
                    enabled: !busy,
                    maxLines: 8,
                    minLines: 6,
                    onChanged: ctrl.updateScript,
                    decoration: const InputDecoration(
                      hintText: 'Write or paste your narration script here…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    style: const TextStyle(fontSize: 15, height: 1.55),
                  ),
                  if (ctrl.project.script.trim().isEmpty && !busy)
                    TextButton.icon(
                      onPressed: ctrl.loadSampleScript,
                      icon: const Icon(Icons.description_outlined, size: 16),
                      label: const Text('Try a sample script'),
                      style: TextButton.styleFrom(
                        foregroundColor: StudioColors.forest,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  if (tags.isNotEmpty) ...[
                    const Divider(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Delivery tags:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: StudioColors.muted,
                          ),
                        ),
                        for (final tag in tags)
                          ActionChip(
                            label: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: StudioColors.forest,
                              ),
                            ),
                            backgroundColor: const Color(0xFFF6F8F3),
                            side: const BorderSide(color: Color(0xFFDCE4D7)),
                            visualDensity: VisualDensity.compact,
                            onPressed: busy ? null : () => _insertTag(tag),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 180, maxHeight: 340),
              child: chunks.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Add a script to preview how it splits into sections.',
                          style: TextStyle(color: StudioColors.muted, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: chunks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = chunks[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 26,
                                child: Text(
                                  '${c.index}.',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: StudioColors.forest,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.text,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, height: 1.4),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${c.words} words · ${c.cached ? "Saved" : "Pending"}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: c.cached
                                            ? StudioColors.forest
                                            : StudioColors.muted,
                                      ),
                                    ),
                                    if (c.warning.isNotEmpty)
                                      Text(
                                        c.warning,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: StudioColors.errorInk,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (c.cached)
                                IconButton(
                                  tooltip: 'Play section',
                                  icon: const Icon(Icons.play_circle_outline, size: 20),
                                  color: StudioColors.forest,
                                  onPressed: () => ctrl.playSection(c),
                                ),
                              IconButton(
                                tooltip: 'Redo section',
                                icon: const Icon(Icons.refresh, size: 20),
                                color: StudioColors.muted,
                                onPressed: busy
                                    ? null
                                    : () => ctrl.runJob(mode: 'redo', redoIndex: c.index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAF7),
              border: Border(top: BorderSide(color: StudioColors.line)),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(
              children: [
                _StatCell(label: 'WORDS', value: '$words'),
                _StatCell(
                  label: 'EST. DURATION',
                  value: _fmtSeconds(ctrl.plan.estimatedSeconds),
                  bordered: true,
                ),
                _StatCell(
                  label: 'SECTIONS',
                  value: '${chunks.length}',
                  bordered: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? StudioColors.forestAccent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? const Color(0xFF283E2C) : StudioColors.muted,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF0EC),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Color(0xFF617263),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool bordered;

  const _StatCell({
    required this.label,
    required this.value,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.only(left: bordered ? 12 : 0),
        decoration: bordered
            ? const BoxDecoration(
                border: Border(left: BorderSide(color: Color(0xFFDCE2D8))),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                letterSpacing: 0.8,
                color: StudioColors.muted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: StudioColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
