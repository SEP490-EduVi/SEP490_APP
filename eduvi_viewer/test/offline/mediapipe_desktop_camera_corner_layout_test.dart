import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera mode uses black background and corner preview layout', () async {
    final stylesFile = File('apps/mediapipe-game-desktop/src/renderer/styles.css');
    final rendererFile = File('apps/mediapipe-game-desktop/src/renderer/renderer.js');

    expect(await stylesFile.exists(), isTrue);
    expect(await rendererFile.exists(), isTrue);

    final css = await stylesFile.readAsString();
    final renderer = await rendererFile.readAsString();
    final cornerRuleMatch = RegExp(
      r'\.stage-body\.camera-corner-mode #game-video\s*\{([^}]*)\}',
      dotAll: true,
    ).firstMatch(css);
    final cornerRule = cornerRuleMatch?.group(1) ?? '';

    expect(css, contains('background: #000;'));
    expect(cornerRuleMatch, isNotNull);
    expect(cornerRule, contains('top: 12px;'));
    expect(cornerRule, contains('right: 16px;'));
    expect(cornerRule, isNot(contains('bottom: 16px;')));

    expect(renderer, contains("classList.add('camera-corner-mode')"));
    expect(renderer, contains("classList.remove('camera-corner-mode')"));
  });
}
