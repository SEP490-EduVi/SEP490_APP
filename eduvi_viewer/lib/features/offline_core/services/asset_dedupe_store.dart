import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/package_manifest.dart';
import 'checksum_service.dart';
import 'offline_storage_paths.dart';

class AssetDedupeStore {
  final OfflineStoragePaths _paths;
  final ChecksumService _checksum;

  AssetDedupeStore({
    OfflineStoragePaths? paths,
    ChecksumService? checksum,
  }) : _paths = paths ?? const OfflineStoragePaths(),
       _checksum = checksum ?? ChecksumService();

  Future<Map<String, dynamic>> persistAssets(List<PackageAssetEntry> assets) async {
    final mapping = <String, dynamic>{};

    for (final asset in assets) {
      if (asset.base64 == null || asset.base64!.isEmpty) {
        continue;
      }

      final bytes = base64Decode(asset.base64!);
      final computedHash = _checksum.sha256Uint8(Uint8List.fromList(bytes));
      final declared = asset.sha256?.trim();
      if (declared != null && declared.isNotEmpty && declared != computedHash) {
        throw FormatException('Asset checksum mismatch for ${asset.assetId}');
      }

      final extension = _extensionForMediaType(asset.mediaType);
      final hashPath = await _paths.sharedAssetByHashPath(
        computedHash,
        extension: extension,
      );
      final hashFile = await _ensureHashFile(hashPath, bytes);

      mapping[asset.assetId] = {
        'assetId': asset.assetId,
        'mediaType': asset.mediaType,
        'sha256': computedHash,
        'bytes': bytes.length,
        'sharedPath': hashFile.path,
        if (asset.relativePath != null) 'relativePath': asset.relativePath,
      };
    }

    return mapping;
  }

  Future<Uri> resolveSharedAssetUri(String sha256Hash, {String extension = '.bin'}) async {
    final path = await _paths.sharedAssetByHashPath(sha256Hash, extension: extension);
    return Uri.file(path);
  }

  Future<String> writeAssetMap(String targetPath, Map<String, dynamic> mapping) async {
    final file = await _writeJsonAtomic(targetPath, mapping);
    return file.path;
  }

  String _extensionForMediaType(String mediaType) {
    switch (mediaType.toLowerCase()) {
      case 'video':
        return '.mp4';
      case 'image':
        return '.img';
      case 'audio':
        return '.mp3';
      case 'model':
        return '.model';
      default:
        return '.bin';
    }
  }

  Future<File> _ensureHashFile(String filePath, List<int> bytes) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);

    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
      return file;
    }

    final existingHash = await _checksum.sha256File(file.path);
    final expected = _checksum.sha256Bytes(bytes);
    if (existingHash != expected) {
      // Rare collision/corruption case, keep deterministic by replacing.
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }

  Future<File> _writeJsonAtomic(String path, Map<String, dynamic> payload) async {
    final file = File(path);
    await file.parent.create(recursive: true);

    final temp = File('$path.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );

    if (await file.exists()) {
      await file.delete();
    }
    return temp.rename(file.path);
  }
}
