import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../../models/block_model.dart';

class TextBlockWidget extends StatelessWidget {
  final EduViBlock block;

  const TextBlockWidget({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final html = block.html;
    if (html.isEmpty) return const SizedBox.shrink();

    return HtmlWidget(
      html,
      textStyle: const TextStyle(
        fontSize: 18,
        height: 1.6,
        color: Color(0xFF334155),
      ),
    );
  }
}
