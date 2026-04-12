import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../../models/block_model.dart';

class HeadingBlockWidget extends StatelessWidget {
  final EduViBlock block;

  const HeadingBlockWidget({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final html = block.html;
    if (html.isEmpty) return const SizedBox.shrink();

    final level = block.headingLevel;
    final wrappedHtml = html.startsWith('<h') ? html : '<h$level>$html</h$level>';

    return HtmlWidget(
      wrappedHtml,
      textStyle: const TextStyle(color: Color(0xFF334155)),
    );
  }
}
