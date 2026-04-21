import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/features/offline_core/domain/launched_electron_process.dart';
import 'package:eduvi_viewer/features/offline_core/services/eduvi_import_service.dart';
import 'package:eduvi_viewer/features/offline_core/services/electron_launcher_service.dart';
import 'package:eduvi_viewer/features/offline_core/services/game_session_manager.dart';
import 'package:eduvi_viewer/features/offline_core/services/local_database_service.dart';
import 'package:eduvi_viewer/features/offline_core/services/offline_storage_paths.dart';

class _FakeElectronLauncher implements ElectronProcessLauncher {
  Map<String, dynamic>? lastContract;

  @override
  Future<LaunchedElectronProcess> launch({
    required String contractPath,
    String? executablePath,
  }) async {
    final contract = jsonDecode(await File(contractPath).readAsString())
        as Map<String, dynamic>;
    lastContract = contract;
    final outputDir = contract['outputDir'] as String;
    final sessionId = contract['sessionId'] as String;
    final packagePath = contract['packagePath'] as String;

    final manifest = jsonDecode(
      await File('$packagePath/package.manifest.json').readAsString(),
    ) as Map<String, dynamic>;
    final packageId = manifest['packageId'] as String;

    final snapshotFile = File('$outputDir/progress.snapshot.json');
    await snapshotFile.writeAsString(
      jsonEncode({
        'snapshotId': 'snap_$sessionId',
        'sessionId': sessionId,
        'packageId': packageId,
        'levelId': 'level_2',
        'checkpoint': 'cp_7',
        'score': 640,
        'timerMsRemaining': 43000,
        'state': {'combo': 4, 'lives': 2},
        'createdAt': DateTime.now().toIso8601String(),
        'checksumSha256': 'snapshot_checksum',
      }),
    );

    final resultFile = File('$outputDir/game.result.json');
    await resultFile.writeAsString(
      jsonEncode({
        'resultId': 'res_$sessionId',
        'sessionId': sessionId,
        'packageId': packageId,
        'status': 'completed',
        'score': 920,
        'durationMs': 180000,
        'accuracy': 0.95,
        'completedAt': DateTime.now().toIso8601String(),
        'detail': {'correct': 47, 'wrong': 3},
      }),
    );

    return LaunchedElectronProcess(pid: 12345, exitCode: Future<int>.value(0));
  }
}

class _FailingElectronLauncher implements ElectronProcessLauncher {
  @override
  Future<LaunchedElectronProcess> launch({
    required String contractPath,
    String? executablePath,
  }) async {
    final contract = jsonDecode(await File(contractPath).readAsString())
        as Map<String, dynamic>;
    final outputDir = contract['outputDir'] as String;

    // Simulate runtime crash with no result file.
    final snapshotFile = File('$outputDir/progress.snapshot.json');
    await snapshotFile.writeAsString(
      jsonEncode({
        'snapshotId': 'snap_crash',
        'levelId': 'level_1',
        'score': 100,
        'timerMsRemaining': 20000,
        'state': {'combo': 1},
        'createdAt': DateTime.now().toIso8601String(),
        'checksumSha256': 'snap_checksum',
      }),
    );

    return LaunchedElectronProcess(pid: 12346, exitCode: Future<int>.value(1));
  }
}

void main() {
  group('offline integration', () {
    late Directory tempDir;
    late OfflineStoragePaths paths;
    late LocalDatabaseService db;
    late GameSessionManager manager;
    late _FakeElectronLauncher fakeLauncher;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('eduvi_offline_integration_');
      paths = OfflineStoragePaths(rootOverride: tempDir.path);
      db = LocalDatabaseService(paths: paths);
      final importService = EduviImportService(paths: paths, database: db);
      fakeLauncher = _FakeElectronLauncher();

      manager = GameSessionManager(
        importService: importService,
        database: db,
        paths: paths,
        launcher: fakeLauncher,
      );
    });

    tearDown(() async {
      await db.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('import -> launch game -> save result locally', () async {
      final file = File('${tempDir.path}/mediapipe_game.eduvi');
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': '1.0.0',
          'packageId': 'pkg_math_001',
          'packageType': 'game',
          'title': 'Math Reflex',
          'version': '1.2.0',
          'entryFile': 'runtime/index.html',
          'games': [
            {
              'templateCode': 'HOVER_SELECT',
              'resultJson': {
                'templateId': 'HOVER_SELECT',
                'scene': {'title': 'Math Reflex'},
                'payload': {
                  'prompt': '1 + 1 = ?',
                  'choices': [
                    {'id': 'A', 'text': '1'},
                    {'id': 'B', 'text': '2'},
                  ],
                  'correctChoiceId': 'B',
                },
              },
            },
          ],
          'assets': const [],
        }),
      );

      final launch = await manager.launchFromEduviFile(file.path);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final packageRow = await db.packageById('pkg_math_001');
      expect(packageRow, isNotNull);

      final sessionRow = await db.sessionById(launch.sessionId);
      expect(sessionRow, isNotNull);
      expect(sessionRow!['state'], 'completed');

      final resultRow = await db.resultBySession(launch.sessionId);
      expect(resultRow, isNotNull);
      expect(resultRow!['status'], 'completed');

      final latestSnapshot = await db.latestSnapshotForSession(launch.sessionId);
      expect(latestSnapshot, isNotNull);
      expect(latestSnapshot!['level_id'], 'level_2');
    });

    test('supports metadata.packageType + games[] eduvi format', () async {
      final file = File('${tempDir.path}/game_metadata_format.eduvi');
      await file.writeAsString(
        jsonEncode({
          'version': '1.1.0',
          'metadata': {
            'title': 'bai 1',
            'packageType': 'game',
          },
          'cards': const [],
          'games': [
            {
              'templateCode': 'HOVER_SELECT',
              'resultJson': {
                'scene': {'title': 'Bai 1'},
                'payload': {
                  'prompt': 'Question',
                  'choices': [
                    {'id': 'A', 'text': 'A'},
                    {'id': 'B', 'text': 'B'},
                  ],
                  'correctChoiceId': 'B',
                },
              },
            },
          ],
        }),
      );

      final launch = await manager.launchFromEduviFile(file.path);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final contractGamePayload = fakeLauncher.lastContract?['gamePayload'];
      expect(contractGamePayload, isA<Map<String, dynamic>>());
      final payload = contractGamePayload as Map<String, dynamic>;
      expect(payload['templateId'], 'HOVER_SELECT');
      expect(payload['payload'], isA<Map<String, dynamic>>());

      final sessionRow = await db.sessionById(launch.sessionId);
      expect(sessionRow, isNotNull);
      expect(sessionRow!['state'], 'completed');
    });

    test('marks session crashed when runtime exits with non-zero code', () async {
      final crashManager = GameSessionManager(
        importService: EduviImportService(paths: paths, database: db),
        database: db,
        paths: paths,
        launcher: _FailingElectronLauncher(),
      );

      final file = File('${tempDir.path}/crash_game.eduvi');
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': '1.0.0',
          'packageId': 'pkg_crash_001',
          'packageType': 'game',
          'title': 'Crash Case',
          'version': '1.0.0',
          'games': [
            {
              'templateCode': 'HOVER_SELECT',
              'resultJson': {'scene': {'title': 'Crash'}},
            },
          ],
        }),
      );

      final launch = await crashManager.launchFromEduviFile(file.path);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final session = await db.sessionById(launch.sessionId);
      expect(session, isNotNull);
      expect(session!['state'], 'crashed');
      expect(session['crash_recovered'], 0);
    });
  });
}
