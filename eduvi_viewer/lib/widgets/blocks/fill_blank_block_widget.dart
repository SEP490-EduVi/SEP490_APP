import 'package:flutter/material.dart';

import '../../models/block_model.dart';

class FillBlankBlockWidget extends StatefulWidget {
  final EduViBlock block;

  const FillBlankBlockWidget({super.key, required this.block});

  @override
  State<FillBlankBlockWidget> createState() => _FillBlankBlockWidgetState();
}

class _FillBlankBlockWidgetState extends State<FillBlankBlockWidget> {
  late List<TextEditingController> _controllers;
  late List<bool?> _results;
  bool _checked = false;
  bool _showAnswers = false;

  List<String> get _blanks => (widget.block.content['blanks'] as List<dynamic>? ?? [])
      .map((b) => b.toString())
      .toList();

  String get _sentence => widget.block.content['sentence'] as String? ?? '';

  String _normalizeAnswerForCompare(String value) {
    var normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    normalized = normalized
        .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
        .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
        .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
        .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
        .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
        .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
        .replaceAll('đ', 'd');
    return normalized;
  }

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_blanks.length, (_) => TextEditingController());
    _results = List.filled(_blanks.length, null);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _check() {
    setState(() {
      _checked = true;
      for (int i = 0; i < _blanks.length; i++) {
        _results[i] = _normalizeAnswerForCompare(_controllers[i].text) ==
            _normalizeAnswerForCompare(_blanks[i]);
      }
    });
  }

  void _reset() {
    setState(() {
      _checked = false;
      _showAnswers = false;
      for (final c in _controllers) {
        c.clear();
      }
      _results = List.filled(_blanks.length, null);
    });
  }

  void _toggleAnswers() {
    setState(() {
      _showAnswers = !_showAnswers;
    });
  }

  @override
  Widget build(BuildContext context) {
    final parts = _sentence.split(RegExp(r'\[.*?\]'));
    int blankIdx = 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < parts.length; i++) ...[
                Text(
                  parts[i],
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                if (i < parts.length - 1 && blankIdx < _blanks.length)
                  _buildBlankField(blankIdx++),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _checked ? _reset : _check,
                child: Text(_checked ? 'Làm lại' : 'Kiểm tra'),
              ),
              OutlinedButton.icon(
                onPressed: _toggleAnswers,
                icon: Icon(_showAnswers ? Icons.visibility_off : Icons.visibility),
                label: Text(_showAnswers ? 'Ẩn đáp án' : 'Xem đáp án'),
              ),
              if (_checked) ...[
                Text(
                  '${_results.where((r) => r == true).length} / ${_blanks.length} đúng',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ],
          ),
          if (_showAnswers) ...[
            const SizedBox(height: 14),
            _buildAnswerPanel(),
          ],
        ],
      ),
    );
  }

  Widget _buildAnswerPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Đáp án đúng',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_blanks.length, (index) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(24),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${index + 1}. ${_blanks[index]}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildBlankField(int index) {
    Color borderColor = Colors.white38;
    if (_checked && _results[index] != null) {
      borderColor = _results[index]! ? Colors.green : Colors.red;
    }

    return Container(
      width: 120,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: TextField(
        controller: _controllers[index],
        enabled: !_checked,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: borderColor, width: 2),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2),
          ),
          disabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: borderColor, width: 2),
          ),
        ),
      ),
    );
  }
}
