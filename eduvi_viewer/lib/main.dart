import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final initialEduViPath = _extractEduViPathArg(args);

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(800, 600),
    center: true,
    title: 'EduVi Viewer',
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(ProviderScope(child: EduViApp(initialEduViPath: initialEduViPath)));
}

String? _extractEduViPathArg(List<String> args) {
  for (final arg in args) {
    if (arg.toLowerCase().endsWith('.eduvi')) {
      return arg;
    }
  }
  return null;
}

class EduViApp extends StatelessWidget {
  final String? initialEduViPath;

  const EduViApp({super.key, this.initialEduViPath});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EduVi Viewer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: HomeScreen(initialFilePath: initialEduViPath),
    );
  }
}
