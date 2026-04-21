import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/eduvi_package_type.dart';
import '../domain/imported_eduvi_package.dart';
import '../domain/package_manifest.dart';
import 'asset_dedupe_store.dart';
import 'package_manifest_parser.dart';
import 'package_path_resolver.dart';
import 'offline_storage_paths.dart';

class PackageManagerService {
  final OfflineStoragePaths _paths;
  final PackageManifestParser _manifestParser;
  final PackagePathResolver _pathResolver;
  final AssetDedupeStore _assetDedupe;

  PackageManagerService({
    OfflineStoragePaths? paths,
    PackageManifestParser? manifestParser,
    PackagePathResolver? pathResolver,
    AssetDedupeStore? assetDedupe,
  }) : _paths = paths ?? const OfflineStoragePaths(),
       _manifestParser = manifestParser ?? PackageManifestParser(),
       _pathResolver =
           pathResolver ?? PackagePathResolver(paths: paths),
       _assetDedupe = assetDedupe ?? AssetDedupeStore(paths: paths);

  Future<ImportedEduviPackage> installFromSource({
    required String sourceFilePath,
    required Map<String, dynamic> rawManifest,
    required EduviPackageType packageType,
    required String checksumSha256,
  }) async {
    await _paths.ensureRootStructure();

    final manifest = _manifestParser.parse(
      raw: rawManifest,
      packageType: packageType,
      sourceFilePath: sourceFilePath,
      calculatedChecksum: checksumSha256,
    );

    final packageRootPath = await _pathResolver.packageRoot(manifest);
    final sourcePath = await _pathResolver.packageSource(manifest);
    final manifestPath = await _pathResolver.packageManifest(manifest);
    final assetMapPath = await _pathResolver.packageAssetMap(manifest);

    final slidePath = await _paths.typedContentPath(
      EduviPackageType.slide,
      manifest.packageId,
      manifest.packageVersion,
    );
    final videoPath = await _paths.packageVideoPath(
      manifest.packageId,
      manifest.packageVersion,
    );
    final gamePath = await _paths.typedContentPath(
      EduviPackageType.game,
      manifest.packageId,
      manifest.packageVersion,
    );

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tempRootPath = '$packageRootPath.__tmp_$stamp';
    final tempSlidePath = '$slidePath.__tmp_$stamp';
    final tempVideoPath = '$videoPath.__tmp_$stamp';
    final tempGamePath = '$gamePath.__tmp_$stamp';

    await _prepareCleanTempDir(tempRootPath);
    await _prepareCleanTempDir(tempSlidePath);
    await _prepareCleanTempDir(tempVideoPath);
    await _prepareCleanTempDir(tempGamePath);

    try {
      await File(sourceFilePath).copy(p.join(tempRootPath, 'source.eduvi'));

      final assetMapping = await _assetDedupe.persistAssets(manifest.assets);
      await _assetDedupe.writeAssetMap(
        p.join(tempRootPath, p.basename(assetMapPath)),
        {
          'packageId': manifest.packageId,
          'packageVersion': manifest.packageVersion,
          'generatedAt': DateTime.now().toIso8601String(),
          'assets': assetMapping,
        },
      );

      await File(p.join(tempRootPath, p.basename(manifestPath))).writeAsString(
        _manifestParser.prettyJson(manifest.toJson()),
      );

      await _writeTypedContent(
        manifest: manifest,
        slideTempPath: tempSlidePath,
        videoTempPath: tempVideoPath,
        gameTempPath: tempGamePath,
      );

      await _replaceDirAtomically(targetPath: packageRootPath, tempPath: tempRootPath);
      await _replaceDirAtomically(targetPath: slidePath, tempPath: tempSlidePath);
      await _replaceDirAtomically(targetPath: videoPath, tempPath: tempVideoPath);
      await _replaceDirAtomically(targetPath: gamePath, tempPath: tempGamePath);

      return ImportedEduviPackage(
        packageId: manifest.packageId,
        packageType: manifest.packageType,
        version: manifest.packageVersion,
        sourceFilePath: sourceFilePath,
        sourcePath: sourcePath,
        packageRootPath: packageRootPath,
        installPath: packageRootPath,
        slideContentPath: slidePath,
        videoContentPath: videoPath,
        gameContentPath: gamePath,
        checksumSha256: checksumSha256,
        manifest: manifest.raw,
      );
    } catch (_) {
      await _safeDelete(tempRootPath);
      await _safeDelete(tempSlidePath);
      await _safeDelete(tempVideoPath);
      await _safeDelete(tempGamePath);
      rethrow;
    }
  }

  Future<void> _writeTypedContent({
    required PackageManifest manifest,
    required String slideTempPath,
    required String videoTempPath,
    required String gameTempPath,
  }) async {
    if (manifest.packageType == EduviPackageType.slide) {
      await File(p.join(slideTempPath, 'deck.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.raw),
      );
    }

    final videoAssets = manifest.assets
        .where((asset) => asset.mediaType.toLowerCase() == 'video')
        .map((asset) => asset.toJson())
        .toList();

    await File(p.join(videoTempPath, 'tracks.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'packageId': manifest.packageId,
        'packageVersion': manifest.packageVersion,
        'tracks': videoAssets,
      }),
    );

    if (manifest.packageType == EduviPackageType.game) {
      final gamePayload = manifest.raw['games'] ?? const <dynamic>[];
      await File(p.join(gameTempPath, 'game_payload.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'packageId': manifest.packageId,
          'packageVersion': manifest.packageVersion,
          'entry': manifest.entry.toJson(),
          'games': gamePayload,
        }),
      );
    }
  }

  Future<void> _replaceDirAtomically({
    required String targetPath,
    required String tempPath,
  }) async {
    final target = Directory(targetPath);
    final temp = Directory(tempPath);
    final backup = Directory('$targetPath.__bak_${DateTime.now().microsecondsSinceEpoch}');

    var movedToBackup = false;
    try {
      if (await target.exists()) {
        await target.rename(backup.path);
        movedToBackup = true;
      }

      await temp.rename(target.path);

      if (movedToBackup && await backup.exists()) {
        await backup.delete(recursive: true);
      }
    } catch (e) {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
      if (movedToBackup && await backup.exists()) {
        if (await target.exists()) {
          await target.delete(recursive: true);
        }
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  Future<void> _prepareCleanTempDir(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }

  Future<void> _safeDelete(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
