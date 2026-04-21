import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop game main enables file access from file origins', () async {
    final mainFile = File('apps/mediapipe-game-desktop/src/main/main.js');
    expect(await mainFile.exists(), isTrue);

    final source = await mainFile.readAsString();
    expect(source, contains("app.commandLine.appendSwitch('allow-file-access-from-files')"));
  });
}