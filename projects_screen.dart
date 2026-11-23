import 'package:flutter/material.dart';

import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class ProjectsScreen extends StatefulWidget {
  final StudioController controller;
  final VoidCallback onProjectOpened;

  const ProjectsScreen({
    super.key,
    required this.controller,
    required this.onProjectOpened,
  });

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final filtered = ctrl.projectList.where((p) {
      if (_query.trim().isEmpty) return true;
      return p.name.toLowerCase().contains(_query.trim().toLowerCase());
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Projects',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.1,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Drafts, sections and mixes saved on this device.',
                    style: TextStyle(fontSize: 12, color: StudioColors.muted),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                ctrl.startNewProject();
                widget.onProjectOpened();
              },
              icon: const Icon(Icons.add, size: 17),
              label: const Text('New'),
              style: FilledButton.styleFrom(
                backgroundColor: StudioColors.lime,
                foregroundColor: StudioColors.limeInk,
                side: const BorderSide(color: StudioColors.limeBorder),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Find a project…',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'No saved projects yet.',
                        style: TextStyle(color: StudioColors.muted, fontSize: 13),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isActive = item.id == ctrl.project.id;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isActive
                                      ? StudioColors.forest
                                      : StudioColors.ink,
                                ),
                              ),
                            ),
                            if (item.ready)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: StudioColors.freeBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Ready',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: StudioColors.freeInk,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${item.words} words · ${item.updated.length >= 10 ? item.updated.substring(0, 10) : ""}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: StudioColors.muted,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete project',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          color: StudioColors.muted,
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete project?'),
                                content: Text(
                                  'Delete "${item.name}" and its saved audio sections?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: StudioColors.errorInk,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await ctrl.deleteProject(item.id);
                            }
                          },
                        ),
                        onTap: () async {
                          await ctrl.openProject(item.id);
                          widget.onProjectOpened();
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
