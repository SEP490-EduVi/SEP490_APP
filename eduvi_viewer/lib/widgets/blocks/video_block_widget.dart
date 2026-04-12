import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../models/block_model.dart';
import '../../services/asset_service.dart';

class VideoBlockWidget extends StatefulWidget {
  final EduViBlock block;
  final AssetService assetService;

  const VideoBlockWidget({
    super.key,
    required this.block,
    required this.assetService,
  });

  @override
  State<VideoBlockWidget> createState() => _VideoBlockWidgetState();
}

class _VideoBlockWidgetState extends State<VideoBlockWidget> {
  Player? _player;
  VideoController? _controller;
  bool _opened = false;
  String? _error;

  bool get _isYouTube => widget.block.provider.toLowerCase() == 'youtube';

  @override
  void initState() {
    super.initState();
    if (_isYouTube) return;
    _player = Player();
    _controller = VideoController(_player!);
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    final src = widget.block.src;
    if (_isYouTube) return;

    try {
      final player = _player;
      if (player == null) return;

      if (src.startsWith('asset://')) {
        final bytes = widget.assetService.resolve(src);
        if (bytes == null) return;

        final mime = widget.assetService.getMimeType(src) ?? 'video/mp4';
        final ext = mime.contains('webm') ? 'webm' : 'mp4';
        final tmpDir = Directory.systemTemp;
        final assetId = src.replaceFirst('asset://', '');
        final tmpFile = File(p.join(tmpDir.path, 'eduvi_$assetId.$ext'));

        if (!await tmpFile.exists()) {
          await tmpFile.writeAsBytes(bytes);
        }

        await player.open(Media(tmpFile.path));
        if (mounted) setState(() => _opened = true);
      } else if (src.startsWith('http')) {
        await player.open(Media(src));
        if (mounted) setState(() => _opened = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Loi cau hinh trinh phat video: $e');
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
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

    if (!_opened && widget.block.src.startsWith('http')) {
      return Container(
        height: 300,
        color: Colors.grey.shade900,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
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
