import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/features/offline_core/domain/eduvi_package_type.dart';
import 'package:eduvi_viewer/features/offline_core/services/checksum_service.dart';
import 'package:eduvi_viewer/features/offline_core/services/offline_storage_paths.dart';
import 'package:eduvi_viewer/features/offline_core/services/package_manager_service.dart';

void main() {
  group('PackageManagerService', () {
    late Directory tempDir;
    late OfflineStoragePaths paths;
    late PackageManagerService manager;
    late ChecksumService checksum;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('eduvi_pkg_manager_test_');
      paths = OfflineStoragePaths(rootOverride: tempDir.path);
      manager = PackageManagerService(paths: paths);
      checksum = ChecksumService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('installs game package into separated root/typed/video folders', () async {
      final sourceFile = File('${tempDir.path}/game.eduvi');
      final assetBytes = utf8.encode('offline_asset_data');
      final assetBase64 = base64Encode(assetBytes);
      final assetHash = checksum.sha256Bytes(assetBytes);

      await sourceFile.writeAsString(
        jsonEncode({
          'schemaVersion': '1.0.0',
          'packageId': 'pkg_game_001',
          'packageType': 'game',
          'title': 'Mediapipe Game',
          'version': '1.0.0',
          'games': [
            {
              'templateCode': 'HOVER_SELECT',
              'resultJson': {'scene': {'title': 'Bai 1'}},
            },
          ],
          'assets': [
            {
              'id': 'video_1',
              'mediaType': 'video',
              'relativePath': 'videos/v1.mp4',
              'base64': assetBase64,
              'sha256': assetHash,
            },
          ],
        }),
      );

      final sourceChecksum = await checksum.sha256File(sourceFile.path);

      final installed = await manager.installFromSource(
        sourceFilePath: sourceFile.path,
        rawManifest: jsonDecode(await sourceFile.readAsString()) as Map<String, dynamic>,
        packageType: EduviPackageType.game,
        checksumSha256: sourceChecksum,
      );

      expect(await File('${installed.installPath}/source.eduvi').exists(), isTrue);
      expect(await File('${installed.installPath}/package.manifest.json').exists(), isTrue);
      expect(await File('${installed.installPath}/map.asset.json').exists(), isTrue);

      expect(installed.gameContentPath, isNotNull);
      expect(await File('${installed.gameContentPath}/game_payload.json').exists(), isTrue);

      expect(installed.videoContentPath, isNotNull);
      expect(await File('${installed.videoContentPath}/tracks.json').exists(), isTrue);

      final sharedRoot = await paths.sharedAssetsPath();
      final sharedFiles = await Directory(sharedRoot)
          .list(recursive: true)
          .where((entity) => entity is File)
          .toList();
      expect(sharedFiles, isNotEmpty);
    });
  });
}
