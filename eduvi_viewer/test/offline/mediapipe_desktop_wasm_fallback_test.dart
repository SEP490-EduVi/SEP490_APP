import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop MediaPipe tracker contains wasm and model fallback candidates', () async {
    final engineFile = File(
      'apps/mediapipe-game-desktop/src/renderer/game/mediapipe-engine.js',
    );
    expect(await engineFile.exists(), isTrue);

    final source = await engineFile.readAsString();
    expect(source, contains('wasmBaseCandidates'));
    expect(source, contains('modelCandidates'));
    expect(source, contains('Failed to initialize vision with wasm base'));

    final wasmCdnFirst = RegExp(
      r"const wasmBaseCandidates = \[\s*DEFAULT_TASKS_VISION_WASM_BASE_URL,\s*TASKS_VISION_WASM_BASE_URL,",
      dotAll: true,
    );
    final modelCdnFirst = RegExp(
      r"const modelCandidates = \[\s*DEFAULT_HAND_LANDMARKER_MODEL_URL,\s*HAND_LANDMARKER_MODEL_URL,",
      dotAll: true,
    );
    expect(wasmCdnFirst.hasMatch(source), isTrue);
    expect(modelCdnFirst.hasMatch(source), isTrue);
  });
}