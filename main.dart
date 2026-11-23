import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'services/studio_controller.dart';
import 'theme/studio_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FishNarratorApp());
}

class FishNarratorApp extends StatefulWidget {
  const FishNarratorApp({super.key});

  @override
  State<FishNarratorApp> createState() => _FishNarratorAppState();
}

class _FishNarratorAppState extends State<FishNarratorApp> {
  final StudioController _controller = StudioController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FishNarrator Studio',
      debugShowCheckedModeBanner: false,
      theme: buildStudioTheme(),
      home: HomeShell(controller: _controller),
    );
  }
}
