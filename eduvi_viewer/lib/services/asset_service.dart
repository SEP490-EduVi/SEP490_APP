import 'dart:typed_data';
import 'dart:io';

import '../models/eduvi_schema.dart';

class AssetService {
  final Map<String, EduViAsset> _assets;
  final Map<String, Uint8List> _bytesCache = {};

  AssetService(this._assets);

  Uint8List? resolve(String src) {
    if (!src.startsWith('asset://')) return null;

    final assetId = src.replaceFirst('asset://', '');
    if (_bytesCache.containsKey(assetId)) return _bytesCache[assetId];

    final asset = _assets[assetId];
    if (asset == null || asset.base64Data.isEmpty) return null;

    try {
      final bytes = asset.bytes;
      _bytesCache[assetId] = bytes;
      return bytes;
    } catch (_) {
      // Allow fallback resolution (e.g. file path) when base64 is placeholder data.
      return null;
    }
  }

  EduViAsset? getAsset(String src) {
    if (!src.startsWith('asset://')) return null;
    final assetId = src.replaceFirst('asset://', '');
    return _assets[assetId];
  }

  String? resolvePlayablePath(String src) {
    final asset = getAsset(src);
    if (asset == null) return null;

    final original = asset.originalUrl.trim();
    if (original.isEmpty) return null;

    if (original.startsWith('file://')) {
      final uri = Uri.tryParse(original);
      if (uri != null && uri.isScheme('file')) {
        final path = uri.toFilePath();
        if (File(path).existsSync()) {
          return path;
        }
      }
      return null;
    }

    if (File(original).existsSync()) {
      return original;
    }
    return null;
  }

  String? getMimeType(String src) {
    if (!src.startsWith('asset://')) return null;
    final assetId = src.replaceFirst('asset://', '');
    return _assets[assetId]?.mimeType;
  }

  bool isVideo(String src) {
    final mime = getMimeType(src) ?? '';
    return mime.startsWith('video/');
  }
}
