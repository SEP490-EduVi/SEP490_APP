import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../models/block_model.dart';
import '../models/eduvi_schema.dart';
import '../services/asset_service.dart';
import '../widgets/blocks/fill_blank_block_widget.dart';
import '../widgets/blocks/flashcard_block_widget.dart';
import '../widgets/blocks/quiz_block_widget.dart';

class VideoPlayerScreen extends StatefulWidget {
  final EduViSchema schema;
  final int initialVideoIndex;

  const VideoPlayerScreen({
    super.key,
    required this.schema,
    this.initialVideoIndex = 0,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final AssetService _assetService;
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;

  late int _videoIndex;
  bool _loading = false;
  String? _error;
  EduViVideoInteraction? _activeInteraction;
  final Set<String> _triggeredInteractions = <String>{};
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;

  List<EduViVideoTrack> get _tracks => widget.schema.videos;
  bool get _hasTracks => _tracks.isNotEmpty;

  EduViVideoTrack? get _currentTrack {
    if (_tracks.isEmpty) {
      return null;
    }
    return _tracks[_videoIndex];
  }

  @override
  void initState() {
    super.initState();
    _assetService = AssetService(widget.schema.assets);
    _player = Player();
    _controller = VideoController(_player);
    _videoIndex = _clampVideoIndex(widget.initialVideoIndex);

    _positionSubscription = _player.stream.position.listen(_handlePositionTick);
    _durationSubscription = _player.stream.duration.listen((d) {
      if (mounted) setState(() => _videoDuration = d);
    });

    if (_hasTracks) {
      unawaited(_openCurrentTrack());
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  int _clampVideoIndex(int index) {
    if (_tracks.isEmpty) return 0;
    if (index < 0) return 0;
    if (index >= _tracks.length) return _tracks.length - 1;
    return index;
  }

  Future<void> _openCurrentTrack() async {
    final track = _currentTrack;
    if (track == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _activeInteraction = null;
      _triggeredInteractions.clear();
    });

    try {
      final media = await _resolveMedia(track.videoUrl);
      if (media == null) {
        throw const FormatException('Không tìm thấy nguồn video hợp lệ trong package.');
      }

      await _player.open(media, play: true);
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Không mở được video: $e';
      });
    }
  }

  Future<Media?> _resolveMedia(String src) async {
    final normalizedSrc = src.trim();
    if (normalizedSrc.isEmpty) {
      return null;
    }

    if (normalizedSrc.startsWith('asset://')) {
      final bytes = _assetService.resolve(normalizedSrc);
      if (bytes != null && bytes.isNotEmpty) {
        final mime = _assetService.getMimeType(normalizedSrc) ?? 'video/mp4';
        final ext = mime.toLowerCase().contains('webm') ? 'webm' : 'mp4';
        final assetId = normalizedSrc
            .replaceFirst('asset://', '')
            .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        final file = File(
          p.join(Directory.systemTemp.path, 'eduvi_video_$assetId.$ext'),
        );

        if (!await file.exists() || await file.length() != bytes.length) {
          await file.writeAsBytes(bytes, flush: true);
        }
        return Media(file.path);
      }

      final playablePath = _assetService.resolvePlayablePath(normalizedSrc);
      if (playablePath != null) {
        return Media(playablePath);
      }
      return null;
    }

    if (normalizedSrc.startsWith('file://')) {
      final uri = Uri.tryParse(normalizedSrc);
      if (uri != null && uri.isScheme('file')) {
        final file = File(uri.toFilePath());
        if (await file.exists()) {
          return Media(file.path);
        }
      }
    }

    if (normalizedSrc.startsWith('http://') || normalizedSrc.startsWith('https://')) {
      return Media(normalizedSrc);
    }

    final file = File(normalizedSrc);
    if (await file.exists()) {
      return Media(file.path);
    }

    return null;
  }

  void _handlePositionTick(Duration position) {
    if (mounted) setState(() => _videoPosition = position);
    final current = _currentTrack;
    if (current == null || _activeInteraction != null) {
      return;
    }

    for (final interaction in current.interactions) {
      if (_triggeredInteractions.contains(interaction.interactionId)) {
        continue;
      }

      final pauseMs = (interaction.pauseTime * 1000).round();
      if (position.inMilliseconds < pauseMs) {
        continue;
      }

      _triggeredInteractions.add(interaction.interactionId);
      _pauseForInteraction(interaction);
      break;
    }
  }

  void _pauseForInteraction(EduViVideoInteraction interaction) {
    _player.pause();
    if (!mounted) return;
    setState(() {
      _activeInteraction = interaction;
    });
  }

  Future<void> _resumeAfterInteraction() async {
    if (!mounted) return;
    setState(() {
      _activeInteraction = null;
    });
    await _player.play();
  }

  Future<void> _seekToDot(EduViVideoInteraction interaction) async {
    final seekTo = Duration(milliseconds: (interaction.pauseTime * 1000).round());
    await _player.seek(seekTo);
    _triggeredInteractions.add(interaction.interactionId);
    _pauseForInteraction(interaction);
  }

  Future<void> _switchVideo(int index) async {
    if (index < 0 || index >= _tracks.length || index == _videoIndex) {
      return;
    }

    await _player.pause();
    if (!mounted) return;

    setState(() {
      _videoIndex = index;
      _error = null;
      _activeInteraction = null;
    });
    await _openCurrentTrack();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasTracks) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video bài giảng')),
        body: const Center(
          child: Text('Package không có video để phát.'),
        ),
      );
    }

    final track = _currentTrack!;
    final packageTitle = widget.schema.metadata.title.trim().isEmpty
        ? 'Video bài giảng'
        : widget.schema.metadata.title.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(packageTitle),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_tracks.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: DropdownButtonFormField<int>(
                      value: _videoIndex,
                      decoration: const InputDecoration(
                        labelText: 'Chọn video',
                      ),
                      items: List.generate(_tracks.length, (index) {
                        final item = _tracks[index];
                        final label = item.productName.trim().isEmpty
                            ? 'Video ${index + 1}'
                            : item.productName.trim();
                        return DropdownMenuItem<int>(
                          value: index,
                          child: Text(label),
                        );
                      }),
                      onChanged: (value) {
                        if (value != null) {
                          _switchVideo(value);
                        }
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: Text(
                    track.productName.trim().isEmpty
                        ? 'Video ${_videoIndex + 1} / ${_tracks.length}'
                        : track.productName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _buildVideoSurface(),
                    ),
                  ),
                ),
              ],
            ),
            if (_activeInteraction != null) _buildInteractionOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 38),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    unawaited(_openCurrentTrack());
                  },
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final track = _currentTrack;
    final hasDots = track != null &&
        track.interactions.isNotEmpty &&
        _videoDuration.inMilliseconds > 0;

    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(hasDots ? 14 : 14),
              topRight: Radius.circular(hasDots ? 14 : 14),
              bottomLeft: Radius.circular(hasDots ? 0 : 14),
              bottomRight: Radius.circular(hasDots ? 0 : 14),
            ),
            child: Container(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Video(controller: _controller, controls: NoVideoControls),
                ),
              ),
            ),
          ),
        ),
        if (track != null)
          _buildInteractionTimeline(track),
      ],
    );
  }

  Widget _buildInteractionTimeline(EduViVideoTrack track) {
    final durationMs = _videoDuration.inMilliseconds;
    final positionMs = _videoPosition.inMilliseconds;
    final remaining = track.interactions
        .where((i) => !_triggeredInteractions.contains(i.interactionId))
        .toList();

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;
          final progress = (durationMs > 0)
              ? (positionMs / durationMs).clamp(0.0, 1.0)
              : 0.0;

          return Stack(
            alignment: Alignment.center,
            children: [
              // Track line (background)
              Positioned(
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Progress fill
              Positioned(
                left: 0,
                child: Container(
                  width: barWidth * progress,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Seekable tap area
              Positioned(
                left: 0,
                right: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) {
                    if (durationMs <= 0) return;
                    final ratio = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                    final seekMs = (ratio * durationMs).round();
                    _player.seek(Duration(milliseconds: seekMs));
                  },
                  child: Container(height: 20, color: Colors.transparent),
                ),
              ),
              // Yellow question dots
              for (final interaction in remaining)
                if (durationMs > 0)
                  Positioned(
                    left: ((interaction.pauseTime * 1000 / durationMs) * barWidth)
                        .clamp(0.0, barWidth - 14),
                    child: GestureDetector(
                      onTap: () => _seekToDot(interaction),
                      child: Tooltip(
                        message: _fallbackInteractionTitle(interaction.normalizedType),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInteractionOverlay() {
    final interaction = _activeInteraction!;
    final interactionBlock = _buildBlockFromInteraction(interaction);
    final title = (interaction.payload['title'] as String?)?.trim();
    final displayTitle = (title != null && title.isNotEmpty)
        ? title
        : _fallbackInteractionTitle(interaction.normalizedType);

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.58),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 650),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            unawaited(_resumeAfterInteraction());
                          },
                          tooltip: 'Đóng',
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Video đang tạm dừng để làm tương tác.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        child: interactionBlock == null
                            ? _buildUnsupportedInteraction(interaction)
                            : _buildInteractionWidget(interactionBlock),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          unawaited(_resumeAfterInteraction());
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Tiếp tục video'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupportedInteraction(EduViVideoInteraction interaction) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFF8FAFC),
      ),
      child: Text(
        'Loại tương tác chưa hỗ trợ: ${interaction.type}',
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildInteractionWidget(EduViBlock block) {
    switch (block.type) {
      case 'QUIZ':
        return QuizBlockWidget(
          block: block,
          onGoNextSlide: () {
            unawaited(_resumeAfterInteraction());
          },
        );
      case 'FLASHCARD':
        return FlashcardBlockWidget(block: block);
      case 'FILL_BLANK':
        return FillBlankBlockWidget(block: block);
      default:
        return const SizedBox.shrink();
    }
  }

  EduViBlock? _buildBlockFromInteraction(EduViVideoInteraction interaction) {
    final payload = interaction.payload;

    switch (interaction.normalizedType) {
      case 'quiz':
        final rawOptions = payload['options'];
        final options = <Map<String, dynamic>>[];

        if (rawOptions is List) {
          for (final rawOption in rawOptions) {
            if (rawOption is Map<String, dynamic>) {
              if (rawOption['text'] is String) {
                options.add(rawOption);
              } else {
                options.add({'text': '${rawOption['value'] ?? rawOption}'});
              }
            } else {
              options.add({'text': '$rawOption'});
            }
          }
        }

        final question = {
          'question': payload['question']?.toString() ?? '',
          'options': options,
          'correctIndex': _toInt(payload['correctIndex']),
          if (payload['explanation'] != null)
            'explanation': payload['explanation'].toString(),
        };

        return EduViBlock(
          id: 'video_quiz_${interaction.interactionId}',
          type: 'QUIZ',
          columnIndex: 0,
          order: 0,
          content: {
            'questions': [question],
          },
        );

      case 'flashcard':
        return EduViBlock(
          id: 'video_flashcard_${interaction.interactionId}',
          type: 'FLASHCARD',
          columnIndex: 0,
          order: 0,
          content: {
            'front': payload['front']?.toString() ?? '',
            'back': payload['back']?.toString() ?? '',
          },
        );

      case 'fill_blank':
        final rawBlanks = payload['blanks'];
        final blanks = rawBlanks is List
            ? rawBlanks.map((item) => '$item').toList()
            : <String>[];

        return EduViBlock(
          id: 'video_fill_blank_${interaction.interactionId}',
          type: 'FILL_BLANK',
          columnIndex: 0,
          order: 0,
          content: {
            'sentence': payload['sentence']?.toString() ?? '',
            'blanks': blanks,
          },
        );

      default:
        return null;
    }
  }

  String _fallbackInteractionTitle(String normalizedType) {
    switch (normalizedType) {
      case 'quiz':
        return 'Câu hỏi tương tác';
      case 'flashcard':
        return 'Flashcard';
      case 'fill_blank':
        return 'Điền từ còn thiếu';
      default:
        return 'Tương tác trong video';
    }
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? -1;
    return -1;
  }
}
