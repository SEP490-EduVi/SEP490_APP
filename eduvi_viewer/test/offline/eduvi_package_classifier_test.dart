import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/features/offline_core/domain/eduvi_package_type.dart';
import 'package:eduvi_viewer/features/offline_core/services/eduvi_package_classifier.dart';

void main() {
  group('EduviPackageClassifier', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('eduvi_classifier_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('classifies cards payload as slide package', () async {
      final file = File('${tempDir.path}/slide.eduvi');
      await file.writeAsString(
        jsonEncode({
          'version': '1.1.0',
          'metadata': {'title': 'Slide package'},
          'cards': [
            {
              'id': 'c1',
              'layouts': [
                {
                  'id': 'l1',
                  'blocks': [
                    {'id': 'b1', 'type': 'TEXT', 'content': {'html': 'A'}},
                  ],
                },
              ],
            },
          ],
        }),
      );

      final classifier = EduviPackageClassifier();
      final type = await classifier.classifyFile(file.path);

      expect(type, EduviPackageType.slide);
    });

    test('classifies explicit game packageType as game', () async {
      final file = File('${tempDir.path}/game.eduvi');
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': '1.0.0',
          'packageId': 'game_001',
          'packageType': 'game',
          'title': 'Mediapipe game',
          'version': '1.0.0',
        }),
      );

      final classifier = EduviPackageClassifier();
      final type = await classifier.classifyFile(file.path);

      expect(type, EduviPackageType.game);
    });

    test('classifies metadata.packageType=game as game package', () async {
      final file = File('${tempDir.path}/game_metadata.eduvi');
      await file.writeAsString(
        jsonEncode({
          'version': '1.1.0',
          'metadata': {
            'title': 'Bai 1',
            'packageType': 'game',
          },
          'cards': [],
        }),
      );

      final classifier = EduviPackageClassifier();
      final type = await classifier.classifyFile(file.path);

      expect(type, EduviPackageType.game);
    });

    test('classifies payload with games array as game package', () async {
      final file = File('${tempDir.path}/game_array.eduvi');
      await file.writeAsString(
        jsonEncode({
          'version': '1.1.0',
          'metadata': {'title': 'Bai 1'},
          'cards': [],
          'games': [
            {
              'templateCode': 'HOVER_SELECT',
              'resultJson': {
                'scene': {'title': 'Bai 1'},
              },
            },
          ],
        }),
      );

      final classifier = EduviPackageClassifier();
      final type = await classifier.classifyFile(file.path);

      expect(type, EduviPackageType.game);
    });
  });
}
