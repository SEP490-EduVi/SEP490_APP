import 'package:flutter/material.dart';

import '../../models/block_model.dart';
import 'mediapipe_game_launcher.dart';

class GameBlockWidget extends StatefulWidget {
  final EduViBlock block;
  final String? runtimeSessionId;

  const GameBlockWidget({
    super.key,
    required this.block,
    this.runtimeSessionId,
  });

  @override
  State<GameBlockWidget> createState() => _GameBlockWidgetState();
}

class _GameBlockWidgetState extends State<GameBlockWidget> {
  final MediaPipeGameLauncher _launcher = MediaPipeGameLauncher();
  bool _launching = false;

  String get _templateId =>
      widget.block.content['templateId'] as String? ?? 'GAME';

  String get _gameName {
    switch (_templateId) {
      case 'HOVER_SELECT':
        return 'Hover Select';
      case 'DRAG_DROP':
        return 'Drag & Drop';
      case 'RUNNER_QUIZ':
        return 'Runner Quiz';
      case 'SNAKE_QUIZ':
        return 'Snake Quiz';
      case 'RUNNER_RACE':
        return 'Runner Race (2P)';
      case 'SNAKE_DUEL':
        return 'Snake Duel (2P)';
      default:
        return 'Game';
    }
  }

  IconData get _gameIcon {
    switch (_templateId) {
      case 'HOVER_SELECT':
      case 'DRAG_DROP':
        return Icons.pan_tool;
      case 'RUNNER_QUIZ':
      case 'RUNNER_RACE':
        return Icons.directions_run;
      case 'SNAKE_QUIZ':
      case 'SNAKE_DUEL':
        return Icons.pest_control;
      default:
        return Icons.sports_esports;
    }
  }

  Future<void> _launchGame() async {
    if (_launching) return;
    setState(() => _launching = true);

    try {
      final pid = await _launcher.launchFromBlockContent(widget.block.content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã mở game $_gameName (PID: $pid)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi mở game: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _launching ? null : _launchGame,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Icon(_gameIcon, size: 40, color: Colors.white),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _gameName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Nhấn để mở game',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (_launching)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  Icons.play_circle_filled,
                  size: 36,
                  color: Colors.white,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
