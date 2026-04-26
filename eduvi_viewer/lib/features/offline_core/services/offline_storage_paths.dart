import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/eduvi_package_type.dart';

class OfflineStoragePaths {
  final String? rootOverride;

  const OfflineStoragePaths({this.rootOverride});

  Future<String> rootPath() async {
    if (rootOverride != null && rootOverride!.trim().isNotEmpty) {
      return rootOverride!;
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      return p.join(localAppData, 'EduviOffline');
    }

    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return p.join(home, '.eduvi_offline');
  }

  Future<String> packagesPath() async => p.join(await rootPath(), 'packages');

  Future<String> slidesPath() async => p.join(await rootPath(), 'slides');

  Future<String> videosPath() async => p.join(await rootPath(), 'videos');

  Future<String> gamesPath() async => p.join(await rootPath(), 'games');

  Future<String> sharedAssetsPath() async => p.join(await rootPath(), 'shared_assets');

  Future<String> sessionsPath() async => p.join(await rootPath(), 'sessions');

  Future<String> dbPath() async => p.join(await rootPath(), 'db');

  Future<String> tempPath() async => p.join(await rootPath(), 'temp');

  Future<String> logsPath() async => p.join(await rootPath(), 'logs');

  Future<String> databaseFilePath() async => p.join(await dbPath(), 'eduvi_offline.db');

  Future<String> packageVersionPath(String packageId, String version) async {
    return p.join(await packagesPath(), packageId, version);
  }

  Future<String> packageManifestPath(String packageId, String version) async {
    return p.join(await packageVersionPath(packageId, version), 'package.manifest.json');
  }

  Future<String> packageSourcePath(String packageId, String version) async {
    return p.join(await packageVersionPath(packageId, version), 'source.eduvi');
  }

  Future<String> packageAssetMapPath(String packageId, String version) async {
    return p.join(await packageVersionPath(packageId, version), 'map.asset.json');
  }

  Future<String> typedContentPath(
    EduviPackageType type,
    String packageId,
    String version,
  ) async {
    final base = switch (type) {
      EduviPackageType.slide => await slidesPath(),
      EduviPackageType.video => await videosPath(),
      EduviPackageType.game => await gamesPath(),
    };
    return p.join(base, packageId, version);
  }

  Future<String> packageVideoPath(String packageId, String version) async {
    return p.join(await videosPath(), packageId, version);
  }

  Future<String> sharedAssetByHashPath(String sha256Hash, {String extension = '.bin'}) async {
    final normalized = sha256Hash.toLowerCase().replaceAll(RegExp(r'[^a-f0-9]'), '');
    final safeHash = normalized.isEmpty ? sha256Hash.toLowerCase() : normalized;
    final lv1 = safeHash.length >= 2 ? safeHash.substring(0, 2) : '00';
    final lv2 = safeHash.length >= 4 ? safeHash.substring(2, 4) : '00';
    return p.join(await sharedAssetsPath(), 'sha256', lv1, lv2, '$safeHash$extension');
  }

  Future<String> appLogPath() async => p.join(await logsPath(), 'app.log');

  Future<String> mediaPipeLogPath() async => p.join(await logsPath(), 'mediapipe.log');

  Future<String> sessionOutputPath(String sessionId) async {
    return p.join(await sessionsPath(), sessionId);
  }

  Future<void> ensureRootStructure() async {
    final dirs = [
      await rootPath(),
      await packagesPath(),
      await slidesPath(),
      await videosPath(),
      await gamesPath(),
      await sharedAssetsPath(),
      await sessionsPath(),
      await dbPath(),
      await tempPath(),
      await logsPath(),
    ];

    for (final dir in dirs) {
      await Directory(dir).create(recursive: true);
    }
  }
}
