import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../domain/eduvi_package_type.dart';
import '../domain/game_launch_contract.dart';
import 'eduvi_import_service.dart';
import 'electron_launcher_service.dart';
import 'game_launch_contract_service.dart';
import 'local_database_service.dart';
import 'offline_storage_paths.dart';
import 'telemetry_local_service.dart';

class GameLaunchReceipt {
  final String packageId;
  final String sessionId;
  final String contractPath;
  final String outputDir;
  final int processId;
  /// Completes with the process exit code when the game runtime exits.
  final Future<int> processExitCode;

  const GameLaunchReceipt({
    required this.packageId,
    required this.sessionId,
    required this.contractPath,
    required this.outputDir,
    required this.processId,
    required this.processExitCode,
  });
}

class GameSessionManager {
  final EduviImportService _importService;
  final LocalDatabaseService _database;
  final OfflineStoragePaths _paths;
  final GameLaunchContractService _contractService;
  final ElectronProcessLauncher _launcher;
  final TelemetryLocalService _telemetry;

  GameSessionManager({
    EduviImportService? importService,
    LocalDatabaseService? database,
    OfflineStoragePaths? paths,
    GameLaunchContractService? contractService,
    ElectronProcessLauncher? launcher,
    TelemetryLocalService? telemetry,
  }) : _paths = paths ?? const OfflineStoragePaths(),
       _database = database ?? LocalDatabaseService(paths: paths),
       _importService = importService ??
           EduviImportService(paths: paths, database: database),
       _contractService = contractService ?? GameLaunchContractService(),
       _launcher = launcher ?? RealElectronProcessLauncher(),
       _telemetry = telemetry ?? TelemetryLocalService(paths: paths);

  Future<GameLaunchReceipt> launchFromEduviFile(
    String sourceFilePath, {
    GameLaunchMode mode = GameLaunchMode.newSession,
  }) async {
    final imported = await _importService.importFromFile(sourceFilePath);
    if (imported.packageType != EduviPackageType.game) {
      throw const FormatException('File eduvi hiện tại không phải package game');
    }

    final sessionId = _buildSessionId(imported.packageId);
    final outputDir = await _paths.sessionOutputPath(sessionId);
    await Directory(outputDir).create(recursive: true);

    final launchContract = GameLaunchContract(
      packagePath: imported.installPath,
      sessionId: sessionId,
      outputDir: outputDir,
      mode: mode,
      entryFile: imported.manifest['entryFile'] as String?,
      gamePayload: _extractGamePayloadForContract(imported.manifest),
    );

    final contractPath = await _contractService.writeContract(launchContract);

    await _database.createSession(
      sessionId: sessionId,
      packageId: imported.packageId,
      mode: mode.value,
      launchContractPath: contractPath,
    );

    final launched = await _launcher.launch(contractPath: contractPath);
    await _telemetry.info(
      'Game runtime launched pid=${launched.pid} package=${imported.packageId} session=$sessionId',
      category: 'session',
    );

    await _database.updateSessionState(sessionId: sessionId, state: 'running');

    unawaited(
      _watchProcess(
        packageId: imported.packageId,
        sessionId: sessionId,
        outputDir: outputDir,
        exitCodeFuture: launched.exitCode,
      ),
    );

    return GameLaunchReceipt(
      packageId: imported.packageId,
      sessionId: sessionId,
      contractPath: contractPath,
      outputDir: outputDir,
      processId: launched.pid,
      processExitCode: launched.exitCode,
    );
  }

  Future<Map<String, Object?>?> latestResumableSession() {
    return _database.latestResumableSession();
  }

  /// Reads the raw `game.result.json` written by the game runtime into [outputDir].
  /// Normalizes between legacy electron format and standard format.
  /// Returns null if the file does not exist or cannot be decoded.
  Future<Map<String, dynamic>?> readSessionResult(String outputDir) async {
    final resultFile = File(p.join(outputDir, 'game.result.json'));
    if (!await resultFile.exists()) return null;
    try {
      final decoded = jsonDecode(await resultFile.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return _normalizeElectronResult(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Converts the electron game result format into the standard display format.
  ///
  /// Electron format:
  /// ```json
  /// { "result": { "correct": 1, "total": 3 }, "finishedAt": "..." }
  /// ```
  /// Standard format used by [GameResultScreen]:
  /// ```json
  /// { "status": "completed", "score": 33, "accuracy": 0.33,
  ///   "durationMs": 0, "completedAt": "..." }
  /// ```
  static Map<String, dynamic> _normalizeElectronResult(
    Map<String, dynamic> raw,
  ) {
    // Already standard format — has explicit score field at top level.
    if (raw.containsKey('score') && !raw.containsKey('result')) return raw;

    final inner = raw['result'];
    final int correct;
    final int total;
    if (inner is Map<String, dynamic>) {
      correct = _asIntStatic(inner['correct']);
      total = _asIntStatic(inner['total']);
    } else {
      correct = 0;
      total = 0;
    }

    final double? accuracy = total > 0 ? correct / total : null;
    // Compute a 0-100 score from correct/total ratio.
    final int score = total > 0 ? ((correct / total) * 100).round() : 0;

    // Duration may come from electron as durationMs or not at all.
    final int durationMs = _asIntStatic(
      raw['durationMs'] ?? raw['duration_ms'] ?? 0,
    );

    final String completedAt =
        (raw['finishedAt'] as String?) ??
        (raw['completedAt'] as String?) ??
        DateTime.now().toIso8601String();

    final String status =
        (raw['status'] as String?) ??
        (raw['finishedAt'] != null ? 'completed' : 'aborted');

    return {
      'status': status,
      'score': score,
      'accuracy': accuracy,
      'durationMs': durationMs,
      'completedAt': completedAt,
      // Keep raw detail for debugging
      'detail': raw,
      // Preserve round breakdown for display
      'correct': correct,
      'total': total,
    };
  }

  static int _asIntStatic(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _watchProcess({
    required String packageId,
    required String sessionId,
    required String outputDir,
    required Future<int> exitCodeFuture,
  }) async {
    final exitCode = await exitCodeFuture;
    await _telemetry.info(
      'Game runtime exited code=$exitCode package=$packageId session=$sessionId',
      category: 'session',
    );

    await _ingestLatestSnapshot(
      packageId: packageId,
      sessionId: sessionId,
      outputDir: outputDir,
    );

    final hasResult = await _ingestResult(
      packageId: packageId,
      sessionId: sessionId,
      outputDir: outputDir,
    );

    if (!hasResult) {
      if (exitCode == 0) {
        await _database.updateSessionState(
          sessionId: sessionId,
          state: 'paused',
        );
        await _telemetry.warn(
          'Session paused without game result package=$packageId session=$sessionId',
          category: 'session',
        );
      } else {
        await _database.updateSessionState(
          sessionId: sessionId,
          state: 'crashed',
          crashRecovered: false,
        );
        await _telemetry.error(
          'Session crashed package=$packageId session=$sessionId exitCode=$exitCode',
          category: 'session',
        );
      }
    }
  }

  Future<void> _ingestLatestSnapshot({
    required String packageId,
    required String sessionId,
    required String outputDir,
  }) async {
    final snapshotFile = File(p.join(outputDir, 'progress.snapshot.json'));
    if (!await snapshotFile.exists()) {
      return;
    }

    try {
      final decoded = jsonDecode(await snapshotFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final payload = <String, Object?>{
        'snapshot_id':
            (decoded['snapshotId'] as String?) ??
            'snap_${DateTime.now().microsecondsSinceEpoch}',
        'session_id': sessionId,
        'package_id': packageId,
        'level_id': (decoded['levelId'] as String?) ?? 'unknown_level',
        'checkpoint': decoded['checkpoint'] as String?,
        'score': _asInt(decoded['score']),
        'timer_ms_remaining': _asInt(decoded['timerMsRemaining']),
        'state_json': jsonEncode(decoded['state'] ?? const <String, dynamic>{}),
        'checksum_sha256':
            (decoded['checksumSha256'] as String?) ?? 'missing_checksum',
        'payload_path': snapshotFile.path,
        'is_valid': 1,
        'created_at':
            (decoded['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
      };

      await _database.saveProgressSnapshot(payload);
    } catch (_) {
      // Ignore malformed snapshot output from runtime and keep session alive.
      await _telemetry.warn(
        'Malformed snapshot output package=$packageId session=$sessionId',
        category: 'session',
      );
    }
  }

  Future<bool> _ingestResult({
    required String packageId,
    required String sessionId,
    required String outputDir,
  }) async {
    final resultFile = File(p.join(outputDir, 'game.result.json'));
    if (!await resultFile.exists()) {
      return false;
    }

    try {
      final decoded = jsonDecode(await resultFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      final payload = <String, Object?>{
        'result_id':
            (decoded['resultId'] as String?) ??
            'res_${DateTime.now().microsecondsSinceEpoch}',
        'session_id': sessionId,
        'package_id': packageId,
        'status': (decoded['status'] as String?) ?? 'completed',
        'score': _asInt(decoded['score']),
        'duration_ms': _asInt(decoded['durationMs']),
        'accuracy': _asDouble(decoded['accuracy']),
        'detail_json': jsonEncode(decoded['detail'] ?? const <String, dynamic>{}),
        'completed_at':
            (decoded['completedAt'] as String?) ?? DateTime.now().toIso8601String(),
      };

      await _database.saveGameResult(payload);
      await _telemetry.info(
        'Saved game result package=$packageId session=$sessionId status=${payload['status']}',
        category: 'session',
      );
      return true;
    } catch (_) {
      await _telemetry.warn(
        'Malformed game result output package=$packageId session=$sessionId',
        category: 'session',
      );
      return false;
    }
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _buildSessionId(String packageId) {
    final rand = Random().nextInt(900000) + 100000;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${packageId}_$stamp$rand';
  }

  Map<String, dynamic>? _extractGamePayloadForContract(
    Map<String, Object?> manifest,
  ) {
    final games = manifest['games'];
    if (games is! List || games.isEmpty) {
      return null;
    }

    final firstGame = games.first;
    if (firstGame is! Map) {
      return null;
    }

    final firstGameMap = _toStringKeyedMap(firstGame);
    final resultJson = _toStringKeyedMap(firstGameMap['resultJson']);
    if (resultJson.isEmpty) {
      return null;
    }

    final templateId =
        _asNonEmptyString(resultJson['templateId']) ??
        _asNonEmptyString(firstGameMap['templateCode']);
    if (templateId == null) {
      return null;
    }

    return <String, dynamic>{
      'gameId':
          _asNonEmptyString(resultJson['gameId']) ??
          _asNonEmptyString(firstGameMap['gameCode']) ??
          'game_$templateId',
      'templateId': templateId,
      'version': _asNonEmptyString(resultJson['version']) ?? '1.0',
      'settings': _toStringKeyedMap(resultJson['settings']),
      'scene': _toStringKeyedMap(resultJson['scene']),
      'payload': _toStringKeyedMap(resultJson['payload']),
    };
  }

  Map<String, dynamic> _toStringKeyedMap(Object? value) {
    if (value is! Map) {
      return <String, dynamic>{};
    }

    return value.map<String, dynamic>((key, mapValue) {
      return MapEntry<String, dynamic>(key.toString(), mapValue);
    });
  }

  String? _asNonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
