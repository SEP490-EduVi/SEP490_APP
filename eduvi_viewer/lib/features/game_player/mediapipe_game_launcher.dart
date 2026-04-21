import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../offline_core/services/offline_storage_paths.dart';

class MediaPipeGameLauncher {
  final OfflineStoragePaths _paths;

  MediaPipeGameLauncher({OfflineStoragePaths? paths})
      : _paths = paths ?? const OfflineStoragePaths();

  Future<int> launchFromBlockContent(Map<String, dynamic> content) async {
    final sessionId = 'inline_${DateTime.now().millisecondsSinceEpoch}';
    final outputDir = await _paths.sessionOutputPath(sessionId);
    await Directory(outputDir).create(recursive: true);

    final extendedContract = <String, dynamic>{
      'packagePath': '',
      'sessionId': sessionId,
      'outputDir': outputDir,
      'mode': 'new',
      'gamePayload': content['gamePayload'] ?? content,
    };

    final contractPath = p.join(outputDir, 'launch.contract.json');
    final encoded =
        const JsonEncoder.withIndent('  ').convert(extendedContract);
    await File(contractPath).writeAsString(encoded);

    final exePath = _resolveGameRuntimePath();
    if (!await File(exePath).exists()) {
      throw FileSystemException(
        'Không tìm thấy MediaPipe game runtime',
        exePath,
      );
    }

    final process = await Process.start(exePath, [
      '--launch-contract=$contractPath',
    ]);
    return process.pid;
  }

  String _resolveGameRuntimePath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      p.join(exeDir, 'game-runtime', 'mediapipe-game.exe'),
      p.join(exeDir, 'game-runtime', 'EduVi Game.exe'),
      p.join(
        Directory.current.path,
        'apps',
        'mediapipe-game-desktop',
        'dist',
        'win-unpacked',
        'EduVi Game.exe',
      ),
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }

    return candidates.first;
  }

  Future<Map<String, dynamic>?> readGameResult(String sessionId) async {
    final outputDir = await _paths.sessionOutputPath(sessionId);
    final resultFile = File(p.join(outputDir, 'game.result.json'));
    if (!await resultFile.exists()) return null;
    final raw = await resultFile.readAsString();
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
