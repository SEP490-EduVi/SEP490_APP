import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/features/offline_core/domain/eduvi_package_type.dart';
import 'package:eduvi_viewer/features/offline_core/services/package_manifest_parser.dart';

void main() {
  group('PackageManifestParser', () {
    final parser = PackageManifestParser();

    test('parses slide package with normalized packageId', () {
      final manifest = parser.parse(
        raw: {
          'version': '1.1.0',
          'metadata': {
            'title': 'Bai hoc so 1',
          },
          'cards': [
            {'id': 'c1'},
          ],
          'assets': [
            {
              'id': 'asset_video_1',
              'mimeType': 'video/mp4',
              'path': 'videos/v1.mp4',
            },
          ],
        },
        packageType: EduviPackageType.slide,
        sourceFilePath: 'D:/tmp/Bai hoc so 1.eduvi',
        calculatedChecksum: 'abc123',
      );

      expect(manifest.packageId, 'bai_hoc_so_1');
      expect(manifest.packageVersion, '1.1.0');
      expect(manifest.assets, hasLength(1));
      expect(manifest.assets.first.mediaType, 'video');
      expect(manifest.integrity.packageSha256, 'abc123');
    });

    test('throws when integrity checksum mismatches source checksum', () {
      expect(
        () => parser.parse(
          raw: {
            'packageId': 'pkg_1',
            'packageType': 'game',
            'title': 'Game 1',
            'version': '1.0.0',
            'games': [
              {'templateCode': 'HOVER_SELECT'},
            ],
            'integrity': {
              'packageSha256': 'declared_checksum',
            },
          },
          packageType: EduviPackageType.game,
          sourceFilePath: 'D:/tmp/game.eduvi',
          calculatedChecksum: 'actual_checksum',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts legacy game package with games[]', () {
      final manifest = parser.parse(
        raw: {
          'metadata': {
            'title': 'Game Legacy',
            'packageType': 'game',
          },
          'version': '1.0.0',
          'cards': const [],
          'games': [
            {
              'templateCode': 'HOVER_SELECT',
              'resultJson': {'scene': {'title': 'Bai 1'}},
            },
          ],
        },
        packageType: EduviPackageType.game,
        sourceFilePath: 'D:/tmp/game_legacy.eduvi',
        calculatedChecksum: 'abc123',
      );

      expect(manifest.packageType, EduviPackageType.game);
      expect(manifest.packageId, 'game_legacy');
    });
  });
}
