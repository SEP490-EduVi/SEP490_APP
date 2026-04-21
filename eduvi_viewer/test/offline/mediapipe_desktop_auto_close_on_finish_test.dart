import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop runtime exposes close-app IPC from main to renderer', () async {
    final mainFile = File('apps/mediapipe-game-desktop/src/main/main.js');
    final preloadFile = File('apps/mediapipe-game-desktop/src/main/preload.js');
    final rendererFile = File('apps/mediapipe-game-desktop/src/renderer/renderer.js');

    expect(await mainFile.exists(), isTrue);
    expect(await preloadFile.exists(), isTrue);
    expect(await rendererFile.exists(), isTrue);

    final mainSource = await mainFile.readAsString();
    final preloadSource = await preloadFile.readAsString();
    final rendererSource = await rendererFile.readAsString();

    expect(mainSource, contains("ipcMain.handle('close-app'"));
    expect(preloadSource, contains("closeApp: () => ipcRenderer.invoke('close-app')"));
    expect(rendererSource, contains('window.electronAPI.closeApp'));
  });
}
