import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drag-drop and hover-select text scale is increased for readability', () async {
    final engineFile = File('apps/mediapipe-game-desktop/src/renderer/game/mediapipe-engine.js');
    expect(await engineFile.exists(), isTrue);

    final source = await engineFile.readAsString();

    expect(source, contains('this.promptFontPx  = 20;'));
    expect(source, contains('minFontPx: 11, maxFontPx: 17, maxLines: 2,'));
    expect(source, isNot(contains('const capH = Math.min(rawRect.h, 74);')));
    expect(source, contains('const capH = Math.max(128, Math.min(rawRect.h * 1.32, 164));'));
    expect(source, contains('minFontPx: 13,'));
    expect(source, contains('maxFontPx: 21,'));
  });
}
