import 'dart:convert';

import 'package:path/path.dart' as p;

import '../domain/eduvi_package_type.dart';
import '../domain/package_manifest.dart';

class PackageManifestParser {
  PackageManifest parse({
    required Map<String, dynamic> raw,
    required EduviPackageType packageType,
    required String sourceFilePath,
    required String calculatedChecksum,
  }) {
    final manifestVersion =
        ('${raw['manifestVersion'] ?? raw['schemaVersion'] ?? raw['version'] ?? '1.0.0'}')
            .trim();

    final packageId = _sanitizeSegment(
      ('${raw['packageId'] ?? raw['id'] ?? raw['metadata']?['title'] ?? p.basenameWithoutExtension(sourceFilePath)}')
          .trim(),
    );

    final packageVersion =
        ('${raw['packageVersion'] ?? raw['version'] ?? '1.0.0'}').trim();

    final title =
        ('${raw['title'] ?? raw['metadata']?['title'] ?? packageId}').trim();

    final entry = PackageEntry(
      slideDeckPath: _readString(raw, ['entry', 'slideDeckPath']),
      gamePayloadPath: _readString(raw, ['entry', 'gamePayloadPath']),
      gameRuntimeEntry:
          _readString(raw, ['entry', 'gameRuntimeEntry']) ??
          (raw['entryFile'] as String?) ??
          (raw['gameRuntime']?['entryFile'] as String?),
    );

    final assets = _parseAssets(raw);

    final declaredPackageSha =
        ('${raw['integrity']?['packageSha256'] ?? raw['checksumSha256'] ?? ''}')
            .trim();

    final integrity = PackageIntegrity(
      packageSha256: declaredPackageSha.isEmpty ? calculatedChecksum : declaredPackageSha,
      offlineReady: raw['integrity']?['offlineReady'] as bool? ?? true,
    );

    final manifest = PackageManifest(
      manifestVersion: manifestVersion.isEmpty ? '1.0.0' : manifestVersion,
      packageId: packageId,
      packageVersion: packageVersion.isEmpty ? '1.0.0' : packageVersion,
      packageType: packageType,
      title: title.isEmpty ? packageId : title,
      entry: entry,
      assets: assets,
      integrity: integrity,
      raw: raw,
    );

    _validateManifest(manifest, calculatedChecksum: calculatedChecksum);
    return manifest;
  }

  List<PackageAssetEntry> _parseAssets(Map<String, dynamic> raw) {
    final result = <PackageAssetEntry>[];
    final assets = raw['assets'];

    if (assets is Map<String, dynamic>) {
      for (final entry in assets.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        result.add(
          PackageAssetEntry(
            assetId: entry.key,
            mediaType: _normalizeMediaType(
              value['kind'] as String? ?? value['mimeType'] as String?,
            ),
            relativePath: value['relativePath'] as String? ??
                value['path'] as String? ??
                value['originalUrl'] as String?,
            sha256: value['sha256'] as String? ?? value['checksumSha256'] as String?,
            bytes: (value['bytes'] as num?)?.toInt() ?? (value['size'] as num?)?.toInt(),
            base64: value['base64'] as String? ?? value['base64Data'] as String?,
          ),
        );
      }
      return result;
    }

    if (assets is List) {
      for (final item in assets) {
        if (item is! Map<String, dynamic>) continue;
        final assetId =
            ('${item['assetId'] ?? item['id'] ?? item['path'] ?? item['relativePath'] ?? 'asset_${result.length + 1}'}')
                .trim();
        result.add(
          PackageAssetEntry(
            assetId: assetId,
            mediaType: _normalizeMediaType(
              item['mediaType'] as String? ??
                  item['kind'] as String? ??
                  item['mimeType'] as String?,
            ),
            relativePath: item['relativePath'] as String? ?? item['path'] as String?,
            sha256: item['sha256'] as String? ?? item['checksumSha256'] as String?,
            bytes: (item['bytes'] as num?)?.toInt() ?? (item['size'] as num?)?.toInt(),
            base64: item['base64'] as String? ?? item['base64Data'] as String?,
          ),
        );
      }
    }

    return result;
  }

  void _validateManifest(PackageManifest manifest, {required String calculatedChecksum}) {
    if (manifest.packageId.trim().isEmpty) {
      throw const FormatException('Manifest packageId không hợp lệ');
    }

    final declared = (manifest.integrity.packageSha256 ?? '').trim();
    if (declared.isNotEmpty && declared != calculatedChecksum) {
      throw const FormatException('Checksum package không khớp với manifest');
    }

    if (manifest.packageType == EduviPackageType.slide) {
      final cards = manifest.raw['cards'];
      if (cards is! List) {
        throw const FormatException('Package slide thiếu trường cards');
      }
    }

    if (manifest.packageType == EduviPackageType.game) {
      final games = manifest.raw['games'];
      final hasRuntime = manifest.raw['gameRuntime'] is Map<String, dynamic>;
      final hasEntryRuntime =
          (manifest.entry.gameRuntimeEntry != null &&
              manifest.entry.gameRuntimeEntry!.trim().isNotEmpty) ||
          ((manifest.raw['entryFile'] as String?)?.trim().isNotEmpty ?? false);

      if ((games is! List || games.isEmpty) && !hasRuntime && !hasEntryRuntime) {
        // Legacy format can still embed game in blocks.
        final cards = manifest.raw['cards'];
        if (cards is! List || cards.isEmpty) {
          throw const FormatException('Package game thiếu games[] hoặc gameRuntime');
        }
      }
    }
  }

  String? _readString(Map<String, dynamic> source, List<String> path) {
    dynamic current = source;
    for (final segment in path) {
      if (current is! Map<String, dynamic>) return null;
      current = current[segment];
    }
    if (current is String && current.trim().isNotEmpty) {
      return current;
    }
    return null;
  }

  String _normalizeMediaType(String? input) {
    final normalized = (input ?? '').trim().toLowerCase();
    if (normalized.startsWith('video/')) return 'video';
    if (normalized.startsWith('image/')) return 'image';
    if (normalized.startsWith('audio/')) return 'audio';
    if (normalized.contains('model') || normalized.contains('mediapipe')) return 'model';
    if (normalized.isEmpty) return 'other';
    return normalized;
  }

  String _sanitizeSegment(String input) {
    final lowercase = input.toLowerCase();
    final normalized = lowercase.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final compact = normalized
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (compact.isEmpty) {
      return 'eduvi_package';
    }
    return compact;
  }

  String prettyJson(Map<String, dynamic> json) {
    return const JsonEncoder.withIndent('  ').convert(json);
  }
}
