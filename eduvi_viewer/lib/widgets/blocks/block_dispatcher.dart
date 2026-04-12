import 'package:flutter/material.dart';

import '../../models/block_model.dart';
import '../../services/asset_service.dart';
import 'fill_blank_block_widget.dart';
import 'flashcard_block_widget.dart';
import 'heading_block_widget.dart';
import 'image_block_widget.dart';
import 'material_block_widget.dart';
import 'quiz_block_widget.dart';
import 'text_block_widget.dart';
import 'video_block_widget.dart';

class BlockDispatcher extends StatelessWidget {
  final EduViBlock block;
  final AssetService assetService;

  const BlockDispatcher({
    super.key,
    required this.block,
    required this.assetService,
  });

  @override
  Widget build(BuildContext context) {
    return switch (block.type) {
      'TEXT' => TextBlockWidget(block: block),
      'HEADING' => HeadingBlockWidget(block: block),
      'IMAGE' => ImageBlockWidget(block: block, assetService: assetService),
      'VIDEO' => VideoBlockWidget(block: block, assetService: assetService),
      'MATERIAL' => MaterialBlockWidget(block: block, assetService: assetService),
      'QUIZ' => QuizBlockWidget(block: block),
      'FLASHCARD' => FlashcardBlockWidget(block: block),
      'FILL_BLANK' => FillBlankBlockWidget(block: block),
      _ => Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey.shade200,
          child: Text('Unsupported block type: ${block.type}'),
        ),
    };
  }
}
