import 'dart:convert';
import 'dart:io';

import '../domain/eduvi_package_type.dart';

class EduviPackageClassifier {
  Future<EduviPackageType> classifyFile(String filePath) async {
    final content = await File(filePath).readAsString();
    final json = jsonDecode(content);
    if (json is! Map<String, dynamic>) {
      return EduviPackageType.slide;
    }
    return classifyJson(json);
  }

  EduviPackageType classifyJson(Map<String, dynamic> json) {
    final declaredType = json['packageType'] as String?;
    if (declaredType != null && declaredType.trim().isNotEmpty) {
      return eduviPackageTypeFromString(declaredType);
    }

    final metadata = json['metadata'];
    if (metadata is Map<String, dynamic>) {
      final metadataType = metadata['packageType'] as String?;
      if (metadataType != null && metadataType.trim().isNotEmpty) {
        return eduviPackageTypeFromString(metadataType);
      }
    }

    final games = json['games'];
    if (games is List && games.isNotEmpty) {
      return EduviPackageType.game;
    }

    if (json['gameRuntime'] is Map<String, dynamic>) {
      return EduviPackageType.game;
    }

    final cards = json['cards'];
    if (cards is List) {
      for (final card in cards) {
        if (card is! Map) continue;
        final layouts = card['layouts'];
        if (layouts is! List) continue;
        for (final layout in layouts) {
          if (layout is! Map) continue;
          final blocks = layout['blocks'];
          if (blocks is! List) continue;
          for (final block in blocks) {
            if (block is! Map) continue;
            final type = ('${block['type'] ?? ''}').toUpperCase();
            if (type == 'GAME') {
              return EduviPackageType.game;
            }
            if (type == 'MATERIAL') {
              final content = block['content'];
              if (content is Map) {
                final widgetType = ('${content['widgetType'] ?? ''}').toUpperCase();
                if (widgetType.contains('GAME') || widgetType.contains('MEDIAPIPE')) {
                  return EduviPackageType.game;
                }
              }
            }
          }
        }
      }
      return EduviPackageType.slide;
    }

    return EduviPackageType.slide;
  }
}
