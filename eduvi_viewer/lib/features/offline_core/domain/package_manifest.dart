import 'eduvi_package_type.dart';

class PackageAssetEntry {
  final String assetId;
  final String mediaType;
  final String? relativePath;
  final String? sha256;
  final int? bytes;
  final String? base64;

  const PackageAssetEntry({
    required this.assetId,
    required this.mediaType,
    this.relativePath,
    this.sha256,
    this.bytes,
    this.base64,
  });

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'mediaType': mediaType,
    if (relativePath != null) 'relativePath': relativePath,
    if (sha256 != null) 'sha256': sha256,
    if (bytes != null) 'bytes': bytes,
  };
}

class PackageEntry {
  final String? slideDeckPath;
  final String? gamePayloadPath;
  final String? gameRuntimeEntry;

  const PackageEntry({
    this.slideDeckPath,
    this.gamePayloadPath,
    this.gameRuntimeEntry,
  });

  Map<String, dynamic> toJson() => {
    if (slideDeckPath != null) 'slideDeckPath': slideDeckPath,
    if (gamePayloadPath != null) 'gamePayloadPath': gamePayloadPath,
    if (gameRuntimeEntry != null) 'gameRuntimeEntry': gameRuntimeEntry,
  };
}

class PackageIntegrity {
  final String? packageSha256;
  final bool offlineReady;

  const PackageIntegrity({
    this.packageSha256,
    this.offlineReady = true,
  });

  Map<String, dynamic> toJson() => {
    if (packageSha256 != null) 'packageSha256': packageSha256,
    'offlineReady': offlineReady,
  };
}

class PackageManifest {
  final String manifestVersion;
  final String packageId;
  final String packageVersion;
  final EduviPackageType packageType;
  final String title;
  final PackageEntry entry;
  final List<PackageAssetEntry> assets;
  final PackageIntegrity integrity;
  final Map<String, dynamic> raw;

  const PackageManifest({
    required this.manifestVersion,
    required this.packageId,
    required this.packageVersion,
    required this.packageType,
    required this.title,
    required this.entry,
    required this.assets,
    required this.integrity,
    required this.raw,
  });

  Map<String, dynamic> toJson() => {
    'manifestVersion': manifestVersion,
    'packageId': packageId,
    'packageVersion': packageVersion,
    'packageType': packageType.value,
    'title': title,
    'entry': entry.toJson(),
    'assets': assets.map((asset) => asset.toJson()).toList(),
    'integrity': integrity.toJson(),
  };
}
