import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../../models/block_model.dart';

class FlashcardBlockWidget extends StatefulWidget {
  final EduViBlock block;

  const FlashcardBlockWidget({super.key, required this.block});

  @override
  State<FlashcardBlockWidget> createState() => _FlashcardBlockWidgetState();
}

class _FlashcardBlockWidgetState extends State<FlashcardBlockWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _showFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  void _flip() {
    if (_showFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    _showFront = !_showFront;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final front = widget.block.content['front'] as String? ?? '';
    final back = widget.block.content['back'] as String? ?? '';

    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * pi;
          final isFrontVisible = angle < pi / 2;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isFrontVisible
                ? _buildSide(front, 'Nhan de lat', Colors.blue.shade800)
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: _buildSide(back, 'Nhan de lat lai', Colors.teal.shade800),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildSide(String html, String hint, Color color) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 200),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HtmlWidget(
            html,
            textStyle: const TextStyle(color: Colors.white, fontSize: 20),
          ),
          const SizedBox(height: 16),
          Text(
            hint,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
