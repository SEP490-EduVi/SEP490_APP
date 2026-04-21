import 'dart:convert';
import 'dart:io';

import '../domain/eduvi_package_type.dart';
import '../domain/imported_eduvi_package.dart';
import 'checksum_service.dart';
import 'eduvi_package_classifier.dart';
import 'local_database_service.dart';
import 'offline_storage_paths.dart';
import 'package_manager_service.dart';
import 'telemetry_local_service.dart';

class EduviImportService {
  final EduviPackageClassifier _classifier;
  final ChecksumService _checksumService;
  final OfflineStoragePaths _paths;
  final LocalDatabaseService _db;
  final PackageManagerService _packageManager;
  final TelemetryLocalService _telemetry;

  EduviImportService({
    EduviPackageClassifier? classifier,
    ChecksumService? checksumService,
    OfflineStoragePaths? paths,
    LocalDatabaseService? database,
    PackageManagerService? packageManager,
    TelemetryLocalService? telemetry,
  }) : _classifier = classifier ?? EduviPackageClassifier(),
       _checksumService = checksumService ?? ChecksumService(),
       _paths = paths ?? const OfflineStoragePaths(),
       _db = database ?? LocalDatabaseService(paths: paths),
       _packageManager = packageManager ?? PackageManagerService(paths: paths),
       _telemetry = telemetry ?? TelemetryLocalService(paths: paths);

  Future<ImportedEduviPackage> importFromFile(String sourceFilePath) async {
    await _paths.ensureRootStructure();

    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Không tìm thấy file eduvi', sourceFilePath);
    }

    final raw = await sourceFile.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Định dạng file eduvi không hợp lệ');
    }

    final manifest = Map<String, dynamic>.from(decoded);
    final packageType = _classifier.classifyJson(manifest);
    final checksum = await _checksumService.sha256File(sourceFilePath);

    _validateManifest(
      sourceFilePath: sourceFilePath,
      manifest: manifest,
      checksum: checksum,
      packageType: packageType,
    );

    final imported = await _packageManager.installFromSource(
      sourceFilePath: sourceFilePath,
      rawManifest: manifest,
      packageType: packageType,
      checksumSha256: checksum,
    );

    await _db.upsertPackage(imported);
    await _telemetry.info(
      'Imported package ${imported.packageId}@${imported.version} (${imported.packageType.value})',
      category: 'importer',
    );
    return imported;
  }

  void _validateManifest({
    required String sourceFilePath,
    required Map<String, dynamic> manifest,
    required String checksum,
    required EduviPackageType packageType,
  }) {
    final declaredChecksum = ('${manifest['checksumSha256'] ?? ''}').trim();
    if (declaredChecksum.isNotEmpty && declaredChecksum != checksum) {
      throw const FormatException('Checksum package không khớp với dữ liệu thực tế');
    }

    final title =
        ('${manifest['title'] ?? manifest['metadata']?['title'] ?? ''}').trim();
    if (title.isEmpty) {
      throw const FormatException('Manifest thiếu title hoặc metadata.title');
    }

    final hasCards = manifest['cards'] is List;
    if (packageType == EduviPackageType.slide && !hasCards) {
      throw const FormatException('Package slide thiếu dữ liệu cards');
    }

    if (packageType == EduviPackageType.game) {
      final games = manifest['games'];
      if (games is! List || games.isEmpty) {
        throw const FormatException('Package game thiếu mảng games[]');
      }
      final firstGame = games.first;
      if (firstGame is! Map<String, dynamic>) {
        throw const FormatException('Phần tử đầu tiên trong games[] không hợp lệ');
      }
      final resultJson = firstGame['resultJson'];
      if (resultJson != null && resultJson is! Map<String, dynamic>) {
        throw const FormatException('games[0].resultJson không hợp lệ');
      }
      final runtime = manifest['gameRuntime'];
      if (runtime != null && runtime is! Map<String, dynamic>) {
        throw const FormatException('Manifest gameRuntime không hợp lệ');
      }
    }
    if (sourceFilePath.trim().isEmpty) {
      throw const FormatException('sourceFilePath không hợp lệ');
    }
  }
}
