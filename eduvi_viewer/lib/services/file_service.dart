import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/eduvi_schema.dart';

EduViSchema _parseSchemaFromString(String jsonString) {
  final json = jsonDecode(jsonString) as Map<String, dynamic>;
  return EduViSchema.fromJson(json);
}

class FileService {
  static Future<String?> pickEduViPath() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['eduvi'],
      dialogTitle: 'Chon file .eduvi',
    );

    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) return null;

    return path;
  }

  static Future<EduViSchema?> pickAndParse() async {
    final path = await pickEduViPath();
    if (path == null) return null;

    return parseFile(path);
  }

  static Future<EduViSchema> parseFile(String filePath) async {
    final file = File(filePath);
    final jsonString = await file.readAsString(encoding: utf8);
    return compute(_parseSchemaFromString, jsonString);
  }

  static EduViSchema parseSchemaJson(String jsonString) {
    return _parseSchemaFromString(jsonString);
  }
}
