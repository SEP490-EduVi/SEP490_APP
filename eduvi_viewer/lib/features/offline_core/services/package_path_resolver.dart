import 'package:path/path.dart' as p;

import '../domain/package_manifest.dart';
import 'offline_storage_paths.dart';

class PackagePathResolver {
  final OfflineStoragePaths _paths;

  const PackagePathResolver({OfflineStoragePaths? paths})
    : _paths = paths ?? const OfflineStoragePaths();

  Future<String> packageRoot(PackageManifest manifest) {
    return _paths.packageVersionPath(manifest.packageId, manifest.packageVersion);
  }

  Future<String> packageSource(PackageManifest manifest) {
    return _paths.packageSourcePath(manifest.packageId, manifest.packageVersion);
  }

  Future<String> packageManifest(PackageManifest manifest) {
    return _paths.packageManifestPath(manifest.packageId, manifest.packageVersion);
  }

  Future<String> packageAssetMap(PackageManifest manifest) {
    return _paths.packageAssetMapPath(manifest.packageId, manifest.packageVersion);
  }

  Future<String> typedContent(PackageManifest manifest) {
    return _paths.typedContentPath(
      manifest.packageType,
      manifest.packageId,
      manifest.packageVersion,
    );
  }

  Future<String> videoContent(PackageManifest manifest) {
    return _paths.packageVideoPath(manifest.packageId, manifest.packageVersion);
  }

  Future<String> resolveAssetLinkPath(
    PackageManifest manifest,
    PackageAssetEntry asset,
  ) async {
    final root = await packageRoot(manifest);
    if (asset.relativePath != null && asset.relativePath!.trim().isNotEmpty) {
      return p.join(root, asset.relativePath!);
    }
    return p.join(root, 'assets', '${asset.assetId}.bin');
  }
}
