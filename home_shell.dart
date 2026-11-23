import 'package:flutter/material.dart';

import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../widgets/audio_monitor_card.dart';
import '../widgets/script_editor_card.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/voice_settings_card.dart';
import 'projects_screen.dart';

class HomeShell extends StatefulWidget {
  final StudioController controller;

  const HomeShell({super.key, required this.controller});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final msg = widget.controller.toastMessage;
    if (msg != null) {
      widget.controller.clearToast();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: StudioColors.dark,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    setState(() {});
  }

  Future<void> _renameProject() async {
    final ctrl = TextEditingController(text: widget.controller.project.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Project title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: FilledButton.styleFrom(
              backgroundColor: StudioColors.lime,
              foregroundColor: StudioColors.limeInk,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) {
      widget.controller.updateProjectName(result);
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SettingsSheet(controller: widget.controller),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    if (!ctrl.initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: StudioColors.dark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.graphic_eq,
                color: StudioColors.lime,
                size: 19,
              ),
            ),
            const SizedBox(width: 9),
            const Text(
              'FishNarrator',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1E4),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                'v2.0',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Color(0xFF47614B),
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton(
              onPressed: _openSettings,
              style: OutlinedButton.styleFrom(
                backgroundColor: StudioColors.paper,
                foregroundColor: const Color(0xFF35483A),
                side: const BorderSide(color: StudioColors.line),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 34),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ctrl.isConfigured
                          ? StudioColors.dotOk
                          : StudioColors.dotWarn,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    ctrl.isConfigured ? 'OpenRouter' : 'Connect',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _navIndex == 0
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Narration studio',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: InkWell(
                                  onTap: _renameProject,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.folder_outlined,
                                        size: 14,
                                        color: StudioColors.muted,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          ctrl.project.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: StudioColors.muted,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.edit,
                                        size: 12,
                                        color: StudioColors.muted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Text(
                                '  ·  ',
                                style: TextStyle(color: StudioColors.muted),
                              ),
                              Text(
                                ctrl.saveState,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: StudioColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: ctrl.job.isRunning ? null : ctrl.startNewProject,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: StudioColors.ink,
                        backgroundColor: StudioColors.paper,
                        side: const BorderSide(color: Color(0xFFD2DBD0)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AudioMonitorCard(controller: ctrl),
                const SizedBox(height: 16),
                ScriptEditorCard(controller: ctrl),
                const SizedBox(height: 16),
                VoiceSettingsCard(controller: ctrl),
              ],
            )
          : ProjectsScreen(
              controller: ctrl,
              onProjectOpened: () => setState(() => _navIndex = 0),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (idx) => setState(() => _navIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_outlined),
            selectedIcon: Icon(Icons.graphic_eq),
            label: 'Studio',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Projects',
          ),
        ],
      ),
    );
  }
}
