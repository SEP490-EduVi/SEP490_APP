import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../features/offline_core/domain/video_track_state.dart';
import '../../features/offline_core/services/video_runtime_service.dart';
import '../../models/block_model.dart';
import '../../services/asset_service.dart';

class VideoBlockWidget extends StatefulWidget {
  final EduViBlock block;
  final AssetService assetService;
  final bool presentationMode;
  final bool isActiveSlide;
  final String? runtimeSessionId;
  final String? runtimeTrackId;

  const VideoBlockWidget({
    super.key,
    required this.block,
    required this.assetService,
    this.presentationMode = false,
    this.isActiveSlide = true,
    this.runtimeSessionId,
    this.runtimeTrackId,
  });

  @override
  State<VideoBlockWidget> createState() => _VideoBlockWidgetState();
}

class _VideoBlockWidgetState extends State<VideoBlockWidget> {
  final VideoRuntimeService _videoRuntime = const VideoRuntimeService();
  Player? _player;
  VideoController? _controller;
  StreamSubscription<Duration>? _positionSubscription;
  bool _opened = false;
  String? _error;
  String? _loadedSource;
  Duration _latestPosition = Duration.zero;

  bool get _isYouTube => widget.block.provider.toLowerCase() == 'youtube';
  bool get _shouldPlayInCurrentContext =>
      !widget.presentationMode || widget.isActiveSlide;
  bool get _canPersistVideoState =>
      widget.runtimeSessionId != null && widget.runtimeSessionId!.trim().isNotEmpty;

  String get _trackId {
    final fromWidget = widget.runtimeTrackId?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) {
      return fromWidget;
    }
    final fromBlock = widget.block.id.trim();
    if (fromBlock.isNotEmpty) {
      return fromBlock;
    }
    return widget.block.src;
  }

  @override
  void initState() {
    super.initState();
    if (_isYouTube) return;
    _syncPlaybackState();
  }

  @override
  void didUpdateWidget(covariant VideoBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isYouTube) return;

    if (oldWidget.isActiveSlide != widget.isActiveSlide ||
        oldWidget.presentationMode != widget.presentationMode ||
        oldWidget.block.src != widget.block.src) {
      _syncPlaybackState();
    }
  }

  Future<void> _syncPlaybackState() async {
    if (_shouldPlayInCurrentContext) {
      await _ensurePlayerReady();
      await _loadVideoIfNeeded();
      await _player?.play();
      return;
    }

    await _player?.pause();
    await _persistPlaybackState(paused: true);
  }

  Future<void> _ensurePlayerReady() async {
    if (_player != null) return;

    final player = Player();
    _player = player;
    _controller = VideoController(player);
    _positionSubscription = player.stream.position.listen((position) {
      _latestPosition = position;
    });

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadVideoIfNeeded() async {
    final src = widget.block.src;
    if (_isYouTube) return;
    if (src.isEmpty || widget.block.missingMedia) return;
    if (_opened && _loadedSource == src) return;

    try {
      final player = _player;
      if (player == null) return;

      _error = null;

      if (src.startsWith('asset://')) {
        final bytes = widget.assetService.resolve(src);
        if (bytes == null) {
          if (mounted) {
            setState(() {
              _error = 'Không tải được dữ liệu video từ asset.';
            });
          }
          return;
        }

        final mime = widget.assetService.getMimeType(src) ?? 'video/mp4';
        final ext = mime.contains('webm') ? 'webm' : 'mp4';
        final tmpDir = Directory.systemTemp;
        final assetId = src.replaceFirst('asset://', '');
        final safeAssetId = assetId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        final tmpFile = File(p.join(tmpDir.path, 'eduvi_$safeAssetId.$ext'));

        if (!await tmpFile.exists()) {
          await tmpFile.writeAsBytes(bytes);
        }

        await player.open(Media(tmpFile.path));
        _loadedSource = src;
        await _restorePlaybackStateIfAny();
        if (mounted) {
          setState(() => _opened = true);
        }
      } else if (src.startsWith('http')) {
        await player.open(Media(src));
        _loadedSource = src;
        await _restorePlaybackStateIfAny();
        if (mounted) {
          setState(() => _opened = true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Loi cau hinh trinh phat video: $e');
      }
    }
  }

  @override
  void dispose() {
    unawaited(_persistPlaybackState(paused: true));
    _positionSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _restorePlaybackStateIfAny() async {
    if (!_canPersistVideoState) return;

    try {
      final state = await _videoRuntime.loadPlaybackState(
        widget.runtimeSessionId!,
        trackId: _trackId,
      );
      if (state == null) {
        return;
      }

      if (state.positionMs > 0) {
        final position = Duration(milliseconds: state.positionMs);
        _latestPosition = position;
        await _player?.seek(position);
      }
    } catch (_) {
      // Keep playback smooth even if persisted state is malformed.
    }
  }

  Future<void> _persistPlaybackState({required bool paused}) async {
    if (!_canPersistVideoState) return;
    if (!_opened) return;

    try {
      await _videoRuntime.savePlaybackState(
        sessionId: widget.runtimeSessionId!,
        state: VideoTrackState(
          trackId: _trackId,
          positionMs: _latestPosition.inMilliseconds,
          paused: paused,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );
    } catch (_) {
      // Ignore persistence failures to avoid interrupting playback UX.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isYouTube) {
      return const SizedBox.shrink();
    }

    if (_error != null) {
      return Container(
        height: 300,
        color: Colors.grey.shade900,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (widget.block.missingMedia || widget.block.src.isEmpty) {
      return Container(
        height: 300,
        color: Colors.grey.shade900,
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white38, size: 48),
        ),
      );
    }

    if (!_shouldPlayInCurrentContext) {
      return Container(
        height: 300,
        color: Colors.grey.shade900,
        child: const Center(
          child: Icon(
            Icons.play_circle_outline,
            color: Colors.white54,
            size: 42,
          ),
        ),
      );
    }

    if (!_opened && widget.block.src.startsWith('http')) {
      return Container(
        height: 300,
        color: Colors.grey.shade900,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (!_opened) {
      return Container(
        height: 300,
        color: Colors.grey.shade900,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: _controller == null
          ? const SizedBox.shrink()
          : Video(controller: _controller!),
    );
  }
}
