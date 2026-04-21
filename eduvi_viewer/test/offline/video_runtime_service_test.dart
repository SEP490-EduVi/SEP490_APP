import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/features/offline_core/domain/video_track_state.dart';
import 'package:eduvi_viewer/features/offline_core/services/offline_storage_paths.dart';
import 'package:eduvi_viewer/features/offline_core/services/video_runtime_service.dart';

void main() {
  group('VideoRuntimeService', () {
    late Directory tempDir;
    late OfflineStoragePaths paths;
    late VideoRuntimeService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('eduvi_video_runtime_test_');
      paths = OfflineStoragePaths(rootOverride: tempDir.path);
      service = VideoRuntimeService(paths: paths);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves and restores playback state by session and track id', () async {
      final state = VideoTrackState(
        trackId: 'video:block#1',
        positionMs: 4567,
        paused: true,
        updatedAt: DateTime.now().toIso8601String(),
      );

      final path = await service.savePlaybackState(
        sessionId: 'session_001',
        state: state,
      );
      expect(await File(path).exists(), isTrue);

      final restored = await service.loadPlaybackState(
        'session_001',
        trackId: 'video:block#1',
      );

      expect(restored, isNotNull);
      expect(restored!.positionMs, 4567);
      expect(restored.paused, isTrue);
      expect(restored.trackId, 'video:block#1');
    });
  });
}
