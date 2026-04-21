import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/features/offline_core/domain/eduvi_package_type.dart';
import 'package:eduvi_viewer/features/offline_core/domain/imported_eduvi_package.dart';
import 'package:eduvi_viewer/features/offline_core/services/local_database_service.dart';
import 'package:eduvi_viewer/features/offline_core/services/offline_storage_paths.dart';

void main() {
  group('LocalDatabaseService', () {
    late Directory tempDir;
    late OfflineStoragePaths paths;
    late LocalDatabaseService db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('eduvi_db_test_');
      paths = OfflineStoragePaths(rootOverride: tempDir.path);
      db = LocalDatabaseService(paths: paths);
    });

    tearDown(() async {
      await db.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('stores package, session, snapshot, and result locally', () async {
      final imported = ImportedEduviPackage(
        packageId: 'pkg_game_001',
        packageType: EduviPackageType.game,
        version: '1.0.0',
        sourceFilePath: 'D:/tmp/game.eduvi',
        installPath: 'D:/tmp/install',
        checksumSha256: 'abc123',
        manifest: const {'title': 'Game 001'},
      );

      await db.upsertPackage(imported);
      final packageRow = await db.packageById(imported.packageId);
      expect(packageRow, isNotNull);
      expect(packageRow!['package_type'], 'game');

      await db.createSession(
        sessionId: 'session_001',
        packageId: imported.packageId,
        mode: 'new',
      );

      await db.saveProgressSnapshot({
        'snapshot_id': 'snap_001',
        'session_id': 'session_001',
        'package_id': imported.packageId,
        'level_id': 'level_1',
        'checkpoint': 'cp_1',
        'score': 100,
        'timer_ms_remaining': 40000,
        'state_json': '{"combo":2}',
        'checksum_sha256': 'snap_checksum',
        'payload_path': '${tempDir.path}/snap.json',
        'is_valid': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      final snapshot = await db.latestSnapshotForSession('session_001');
      expect(snapshot, isNotNull);
      expect(snapshot!['snapshot_id'], 'snap_001');

      await db.saveGameResult({
        'result_id': 'res_001',
        'session_id': 'session_001',
        'package_id': imported.packageId,
        'status': 'completed',
        'score': 920,
        'duration_ms': 180000,
        'accuracy': 0.94,
        'detail_json': '{"correct":47}',
        'completed_at': DateTime.now().toIso8601String(),
      });

      final result = await db.resultBySession('session_001');
      expect(result, isNotNull);
      expect(result!['result_id'], 'res_001');

      final session = await db.sessionById('session_001');
      expect(session, isNotNull);
      expect(session!['state'], 'completed');
    });
  });
}
