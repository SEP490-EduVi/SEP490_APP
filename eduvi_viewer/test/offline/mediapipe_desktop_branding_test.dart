import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop runtime uses EduVi branding icon and title', () async {
    final packageFile = File('apps/mediapipe-game-desktop/package.json');
    final indexFile = File('apps/mediapipe-game-desktop/src/renderer/index.html');
    final iconFile = File('apps/mediapipe-game-desktop/assets/icon.ico');

    expect(await packageFile.exists(), isTrue);
    expect(await indexFile.exists(), isTrue);

    final packageJson = jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
    final build = packageJson['build'] as Map<String, dynamic>;
    final win = build['win'] as Map<String, dynamic>;
    final html = await indexFile.readAsString();

    expect(win['icon'], 'assets/icon.ico');
    expect(await iconFile.exists(), isTrue);
    expect(html, contains('<title>EduVi Game Player</title>'));
    expect(html, isNot(contains('🎮')));
  });
}
