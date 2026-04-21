import 'dart:convert';
import 'dart:io';

import '../../../models/eduvi_schema.dart';
import '../domain/imported_eduvi_package.dart';
import '../../../services/file_service.dart';

class SlideRuntimeService {
  Future<EduViSchema> loadDeck(ImportedEduviPackage package) async {
    final extractedPath = package.slideContentPath;
    if (extractedPath != null && extractedPath.trim().isNotEmpty) {
      final deckFile = File('$extractedPath/deck.json');
      if (await deckFile.exists()) {
        final decoded = jsonDecode(await deckFile.readAsString());
        if (decoded is Map<String, dynamic>) {
          return EduViSchema.fromJson(decoded);
        }
      }
    }

    final sourcePath = package.sourcePath ?? package.sourceFilePath;
    return FileService.parseFile(sourcePath);
  }
}
