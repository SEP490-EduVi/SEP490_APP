import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/features/offline_core/domain/eduvi_package_type.dart';
import 'package:eduvi_viewer/features/offline_core/domain/imported_eduvi_package.dart';
import 'package:eduvi_viewer/features/offline_core/services/slide_runtime_service.dart';

void main() {
  group('SlideRuntimeService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('eduvi_slide_runtime_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('loads deck from extracted slide content when available', () async {
      final slideDir = Directory('${tempDir.path}/slides/pkg_1/1.0.0');
      await slideDir.create(recursive: true);

      final deck = {
        'version': '1.1.0',
        'metadata': {
          'title': 'Deck Tu Offline Content',
        },
        'cards': [
          {
            'id': 'card_1',
            'order': 0,
            'layouts': [
              {
                'id': 'layout_1',
                'order': 0,
                'blocks': [
                  {
                    'id': 'block_1',
                    'type': 'TEXT',
                    'columnIndex': 0,
                    'order': 0,
                    'content': {'html': '<p>Hello</p>'},
                  },
                ],
              },
            ],
          },
        ],
      };

      await File('${slideDir.path}/deck.json').writeAsString(jsonEncode(deck));
      await File('${tempDir.path}/source.eduvi').writeAsString('{}');

      final imported = ImportedEduviPackage(
        packageId: 'pkg_1',
        packageType: EduviPackageType.slide,
        version: '1.0.0',
        sourceFilePath: '${tempDir.path}/source.eduvi',
        sourcePath: '${tempDir.path}/source.eduvi',
        packageRootPath: '${tempDir.path}/packages/pkg_1/1.0.0',
        installPath: '${tempDir.path}/packages/pkg_1/1.0.0',
        slideContentPath: slideDir.path,
        checksumSha256: 'abc123',
        manifest: const {'title': 'Deck Tu Source'},
      );

      final service = SlideRuntimeService();
      final schema = await service.loadDeck(imported);

      expect(schema.metadata.title, 'Deck Tu Offline Content');
      expect(schema.cards, hasLength(1));
    });
  });
}
