import 'eduvi_package_type.dart';

class ImportedEduviPackage {
  final String packageId;
  final EduviPackageType packageType;
  final String version;
  final String sourceFilePath;
  final String? sourcePath;
  final String? packageRootPath;
  final String installPath;
  final String? slideContentPath;
  final String? videoContentPath;
  final String? gameContentPath;
  final String checksumSha256;
  final Map<String, dynamic> manifest;

  const ImportedEduviPackage({
    required this.packageId,
    required this.packageType,
    required this.version,
    required this.sourceFilePath,
    this.sourcePath,
    this.packageRootPath,
    required this.installPath,
    this.slideContentPath,
    this.videoContentPath,
    this.gameContentPath,
    required this.checksumSha256,
    required this.manifest,
  });
}
