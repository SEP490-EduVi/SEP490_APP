import 'package:flutter/material.dart';

import '../../models/block_model.dart';

class QuizBlockWidget extends StatefulWidget {
  final EduViBlock block;
  final VoidCallback? onGoNextSlide;

  const QuizBlockWidget({
    super.key,
    required this.block,
    this.onGoNextSlide,
  });

  @override
  State<QuizBlockWidget> createState() => _QuizBlockWidgetState();
}

class _QuizBlockWidgetState extends State<QuizBlockWidget> {
  int _currentQ = 0;
  int? _selectedOption;
  bool _showResult = false;
  int _score = 0;

  List<dynamic> get _questions =>
      widget.block.content['questions'] as List<dynamic>? ?? [];

  Map<String, dynamic> get _currentQuestion =>
      _questions[_currentQ] as Map<String, dynamic>;

  void _selectOption(int index) {
    if (_showResult) return;
    final correctIndex = _currentQuestion['correctIndex'] as int? ?? -1;
    setState(() {
      _selectedOption = index;
      _showResult = true;
      if (index == correctIndex) _score++;
    });
  }

  void _nextQuestion() {
    setState(() {
      _currentQ++;
      _selectedOption = null;
      _showResult = false;
    });
  }

  void _handlePrimaryAction() {
    if (_currentQ + 1 < _questions.length) {
      _nextQuestion();
      return;
    }

    if (widget.onGoNextSlide != null) {
      widget.onGoNextSlide!.call();
      return;
    }

    _nextQuestion();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_questions.isEmpty) {
      return Center(
        child: Text(
          'Không có câu hỏi',
          style: TextStyle(color: colorScheme.onSurface),
        ),
      );
    }

    if (_currentQ >= _questions.length) {
      return _buildScoreCard();
    }

    final q = _currentQuestion;
    final options = q['options'] as List<dynamic>? ?? [];
    final correctIndex = q['correctIndex'] as int? ?? -1;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Câu ${_currentQ + 1} / ${_questions.length}',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            q['question'] as String? ?? '',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < options.length; i++) ...[
            _buildOption(i, options[i] as Map<String, dynamic>, correctIndex, colorScheme),
            const SizedBox(height: 8),
          ],
          if (_showResult && q['explanation'] != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                q['explanation'] as String,
                style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 15),
              ),
            ),
          ],
          if (_showResult) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _handlePrimaryAction,
                child: Text(
                  _currentQ + 1 < _questions.length
                      ? 'Câu tiếp'
                      : (widget.onGoNextSlide != null ? 'Qua trang sau' : 'Xem kết quả'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOption(
    int index,
    Map<String, dynamic> option,
    int correctIndex,
    ColorScheme colorScheme,
  ) {
    Color bg = colorScheme.surfaceContainerHighest;
    Color border = colorScheme.outlineVariant;

    if (_showResult) {
      if (index == correctIndex) {
        bg = const Color(0xFFE8F8EE);
        border = const Color(0xFF16A34A);
      } else if (index == _selectedOption) {
        bg = const Color(0xFFFEECEC);
        border = const Color(0xFFDC2626);
      }
    } else if (index == _selectedOption) {
      border = colorScheme.primary;
    }

    return GestureDetector(
      onTap: () => _selectOption(index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Text(
          option['text'] as String? ?? '',
          style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events, size: 64, color: Color(0xFF2563EB)),
          const SizedBox(height: 16),
          Text(
            '$_score / ${_questions.length}',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _score == _questions.length ? 'Xuất sắc!' : 'Cố gắng hơn nhé!',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 18),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _currentQ = 0;
                _selectedOption = null;
                _showResult = false;
                _score = 0;
              });
            },
            child: const Text('Làm lại'),
          ),
        ],
      ),
    );
  }
}
