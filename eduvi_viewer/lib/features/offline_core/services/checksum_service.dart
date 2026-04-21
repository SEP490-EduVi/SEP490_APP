import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class ChecksumService {
  Future<String> sha256File(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return sha256.convert(bytes).toString();
  }

  String sha256Bytes(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  String sha256Uint8(Uint8List bytes) {
    return sha256Bytes(bytes);
  }

  String sha256Text(String text) {
    return sha256.convert(text.codeUnits).toString();
  }
}
