import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home screen stores readable game history title from file path', () async {
    final homeFile = File('lib/screens/home_screen.dart');
    expect(await homeFile.exists(), isTrue);

    final source = await homeFile.readAsString();
    expect(source, isNot(contains("title: 'Game \${launch.packageId}'")));
    expect(source, contains('title: _extractDisplayNameFromPath(openedPath)'));
  });
}
