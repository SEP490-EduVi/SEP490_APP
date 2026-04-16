import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/services/file_service.dart';

void main() {
  test('parseSchemaJson parses minimal eduvi payload', () {
    final jsonText = jsonEncode({
      'version': '1.0.0',
      'exportedAt': '',
      'metadata': {'title': 'T'},
      'cards': [],
      'assets': {},
    });

    final schema = FileService.parseSchemaJson(jsonText);
    expect(schema.metadata.title, 'T');
  });
}
