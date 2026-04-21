import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/video_track_state.dart';
import 'offline_storage_paths.dart';

class VideoRuntimeService {
  final OfflineStoragePaths _paths;

  const VideoRuntimeService({OfflineStoragePaths? paths})
    : _paths = paths ?? const OfflineStoragePaths();

  Future<String> savePlaybackState({
    required String sessionId,
    required VideoTrackState state,
  }) async {
    final trackId = _sanitizeTrackId(state.trackId);
    final dirPath = await _paths.sessionOutputPath(sessionId);
    final filePath = p.join(dirPath, 'video.$trackId.state.json');

    final file = await _writeJsonAtomic(filePath, state.toJson());
    return file.path;
  }

  Future<VideoTrackState?> loadPlaybackState(
    String sessionId, {
    required String trackId,
  }) async {
    final safeTrack = _sanitizeTrackId(trackId);
    final dirPath = await _paths.sessionOutputPath(sessionId);
    final filePath = p.join(dirPath, 'video.$safeTrack.state.json');
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return VideoTrackState.fromJson(decoded);
  }

  String _sanitizeTrackId(String input) {
    final normalized = input.trim().toLowerCase();
    final replaced = normalized.replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    final compact = replaced
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return compact.isEmpty ? 'default' : compact;
  }

  Future<File> _writeJsonAtomic(String path, Map<String, dynamic> payload) async {
    final file = File(path);
    await file.parent.create(recursive: true);

    final tempFile = File('$path.tmp');
    await tempFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );

    if (await file.exists()) {
      await file.delete();
    }
    return tempFile.rename(path);
  }
}
