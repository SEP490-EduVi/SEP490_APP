import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime does not expose launcher game list or back button to users', () async {
    final indexFile = File('apps/mediapipe-game-desktop/src/renderer/index.html');
    final rendererFile = File('apps/mediapipe-game-desktop/src/renderer/renderer.js');

    expect(await indexFile.exists(), isTrue);
    expect(await rendererFile.exists(), isTrue);

    final html = await indexFile.readAsString();
    final renderer = await rendererFile.readAsString();

    expect(html, contains('<section id="launcher" class="hidden">'));
    expect(html, isNot(contains('id="game-grid"')));
    expect(html, isNot(contains('id="btn-back"')));
    expect(renderer, isNot(contains("getElementById('btn-back')")));
    expect(renderer, isNot(contains('renderGameCards();')));
  });
}
