import 'dart:io';

import 'offline_storage_paths.dart';

class TelemetryLocalService {
  final OfflineStoragePaths _paths;

  const TelemetryLocalService({OfflineStoragePaths? paths})
    : _paths = paths ?? const OfflineStoragePaths();

  Future<void> info(String message, {String category = 'app'}) {
    return _write(level: 'INFO', message: message, category: category);
  }

  Future<void> warn(String message, {String category = 'app'}) {
    return _write(level: 'WARN', message: message, category: category);
  }

  Future<void> error(String message, {String category = 'app'}) {
    return _write(level: 'ERROR', message: message, category: category);
  }

  Future<void> _write({
    required String level,
    required String message,
    required String category,
  }) async {
    await _paths.ensureRootStructure();
    final line = '[${DateTime.now().toIso8601String()}][$level][$category] $message\n';

    final targetPath = category.toLowerCase().contains('mediapipe')
        ? await _paths.mediaPipeLogPath()
        : await _paths.appLogPath();

    final file = File(targetPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite(mode: FileMode.append);
    sink.write(line);
    await sink.flush();
    await sink.close();
  }
}
