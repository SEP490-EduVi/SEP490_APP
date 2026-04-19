import 'dart:typed_data';

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

    final bytes = asset.bytes;
    _bytesCache[assetId] = bytes;
    return bytes;
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
