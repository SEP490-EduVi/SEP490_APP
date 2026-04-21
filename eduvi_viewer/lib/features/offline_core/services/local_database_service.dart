import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/imported_eduvi_package.dart';
import 'offline_storage_paths.dart';

class LocalDatabaseService {
  final OfflineStoragePaths _paths;
  Database? _database;

  LocalDatabaseService({OfflineStoragePaths? paths})
    : _paths = paths ?? const OfflineStoragePaths();

  Future<Database> _open() async {
    if (_database != null) {
      return _database!;
    }

    await _paths.ensureRootStructure();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbFilePath = await _paths.databaseFilePath();
    _database = await databaseFactory.openDatabase(
      dbFilePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await _createSchema(db);
        },
      ),
    );
    return _database!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS packages (
        package_id TEXT PRIMARY KEY,
        package_type TEXT NOT NULL CHECK (package_type IN ('slide', 'game')),
        title TEXT NOT NULL,
        version TEXT NOT NULL,
        source_file_path TEXT NOT NULL,
        install_path TEXT NOT NULL,
        checksum_sha256 TEXT NOT NULL,
        manifest_json TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        installed_at TEXT NOT NULL,
        last_opened_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        session_id TEXT PRIMARY KEY,
        package_id TEXT NOT NULL,
        mode TEXT NOT NULL CHECK (mode IN ('new', 'resume')),
        state TEXT NOT NULL CHECK (state IN ('created', 'running', 'paused', 'completed', 'crashed')),
        launch_contract_path TEXT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        last_activity_at TEXT NOT NULL,
        last_snapshot_id TEXT,
        crash_recovered INTEGER NOT NULL DEFAULT 0 CHECK (crash_recovered IN (0, 1)),
        FOREIGN KEY (package_id) REFERENCES packages(package_id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS progress_snapshots (
        snapshot_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        package_id TEXT NOT NULL,
        level_id TEXT NOT NULL,
        checkpoint TEXT,
        score INTEGER NOT NULL,
        timer_ms_remaining INTEGER NOT NULL DEFAULT 0,
        state_json TEXT NOT NULL,
        checksum_sha256 TEXT NOT NULL,
        payload_path TEXT,
        is_valid INTEGER NOT NULL DEFAULT 1 CHECK (is_valid IN (0, 1)),
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
        FOREIGN KEY (package_id) REFERENCES packages(package_id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS game_results (
        result_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        package_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('completed', 'failed', 'aborted')),
        score INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        accuracy REAL,
        detail_json TEXT,
        completed_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
        FOREIGN KEY (package_id) REFERENCES packages(package_id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_packages_type_active ON packages(package_type, is_active)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_package_started ON sessions(package_id, started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_snapshots_session_created ON progress_snapshots(session_id, created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_results_package_completed ON game_results(package_id, completed_at DESC)',
    );
  }

  Future<void> upsertPackage(ImportedEduviPackage package) async {
    final db = await _open();
    final now = DateTime.now().toIso8601String();
    await db.insert('packages', {
      'package_id': package.packageId,
      'package_type': package.packageType.name == 'game' ? 'game' : 'slide',
      'title':
          ('${package.manifest['title'] ?? package.manifest['metadata']?['title'] ?? package.packageId}'),
      'version': package.version,
      'source_file_path': package.sourceFilePath,
      'install_path': package.installPath,
      'checksum_sha256': package.checksumSha256,
      'manifest_json': jsonEncode(package.manifest),
      'is_active': 1,
      'installed_at': now,
      'last_opened_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>?> packageById(String packageId) async {
    final db = await _open();
    final rows = await db.query(
      'packages',
      where: 'package_id = ?',
      whereArgs: [packageId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> createSession({
    required String sessionId,
    required String packageId,
    required String mode,
    String state = 'created',
    String? launchContractPath,
  }) async {
    final db = await _open();
    final now = DateTime.now().toIso8601String();
    await db.insert('sessions', {
      'session_id': sessionId,
      'package_id': packageId,
      'mode': mode,
      'state': state,
      'launch_contract_path': launchContractPath,
      'started_at': now,
      'last_activity_at': now,
      'crash_recovered': 0,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> updateSessionState({
    required String sessionId,
    required String state,
    String? endedAt,
    String? lastSnapshotId,
    bool? crashRecovered,
  }) async {
    final db = await _open();
    final values = <String, Object?>{
      'state': state,
      'last_activity_at': DateTime.now().toIso8601String(),
    };
    if (endedAt != null) values['ended_at'] = endedAt;
    if (lastSnapshotId != null) values['last_snapshot_id'] = lastSnapshotId;
    if (crashRecovered != null) values['crash_recovered'] = crashRecovered ? 1 : 0;

    await db.update(
      'sessions',
      values,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<Map<String, Object?>?> latestResumableSession() async {
    final db = await _open();
    final rows = await db.query(
      'sessions',
      where: 'state IN (?, ?, ?)',
      whereArgs: ['running', 'paused', 'crashed'],
      orderBy: 'last_activity_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> sessionById(String sessionId) async {
    final db = await _open();
    final rows = await db.query(
      'sessions',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveProgressSnapshot(Map<String, Object?> payload) async {
    final db = await _open();
    await db.insert('progress_snapshots', payload, conflictAlgorithm: ConflictAlgorithm.replace);
    final sessionId = payload['session_id'] as String;
    final snapshotId = payload['snapshot_id'] as String;
    await updateSessionState(
      sessionId: sessionId,
      state: 'running',
      lastSnapshotId: snapshotId,
    );
  }

  Future<Map<String, Object?>?> latestSnapshotForSession(String sessionId) async {
    final db = await _open();
    final rows = await db.query(
      'progress_snapshots',
      where: 'session_id = ? AND is_valid = 1',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveGameResult(Map<String, Object?> payload) async {
    final db = await _open();
    await db.insert('game_results', payload, conflictAlgorithm: ConflictAlgorithm.replace);
    final sessionId = payload['session_id'] as String;
    await updateSessionState(
      sessionId: sessionId,
      state: 'completed',
      endedAt: DateTime.now().toIso8601String(),
    );
  }

  Future<Map<String, Object?>?> resultBySession(String sessionId) async {
    final db = await _open();
    final rows = await db.query(
      'game_results',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'completed_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setAppSetting(String key, String value) async {
    final db = await _open();
    await db.insert('app_settings', {
      'setting_key': key,
      'setting_value': value,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getAppSetting(String key) async {
    final db = await _open();
    final rows = await db.query(
      'app_settings',
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['setting_value'] as String?;
  }

  Future<void> dispose() async {
    final db = _database;
    _database = null;
    if (db != null) {
      await db.close();
    }
  }

  Future<String> debugDatabasePath() async {
    return p.normalize(await _paths.databaseFilePath());
  }
}
