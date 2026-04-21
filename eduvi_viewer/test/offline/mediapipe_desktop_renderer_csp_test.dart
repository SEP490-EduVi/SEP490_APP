import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop renderer CSP allows jsdelivr scripts for MediaPipe modules', () async {
    final indexFile = File('apps/mediapipe-game-desktop/src/renderer/index.html');
    expect(await indexFile.exists(), isTrue);

    final html = await indexFile.readAsString();
    expect(html, contains("script-src 'self' 'unsafe-inline'"));
    expect(html, contains('https://cdn.jsdelivr.net'));
    expect(html, contains("'wasm-unsafe-eval'"));
    expect(html, contains("'unsafe-eval'"));
  });
}