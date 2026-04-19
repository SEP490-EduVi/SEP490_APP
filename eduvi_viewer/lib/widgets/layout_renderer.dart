import 'package:flutter/material.dart';

import '../models/layout_model.dart';
import '../services/asset_service.dart';
import 'blocks/block_dispatcher.dart';

class LayoutRenderer extends StatelessWidget {
  final EduViLayout layout;
  final AssetService assetService;
  final VoidCallback? onNextSlide;
  final bool presentationMode;
  final bool isActiveSlide;

  const LayoutRenderer({
    super.key,
    required this.layout,
    required this.assetService,
    this.onNextSlide,
    this.presentationMode = false,
    this.isActiveSlide = true,
  });

  @override
  Widget build(BuildContext context) {
    if (layout.columnCount <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final block in layout.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BlockDispatcher(
                block: block,
                assetService: assetService,
                onNextSlide: onNextSlide,
                presentationMode: presentationMode,
                isActiveSlide: isActiveSlide,
              ),
            ),
        ],
      );
    }

    final columns = List.generate(
      layout.columnCount,
      (col) => layout.blocks.where((b) => b.columnIndex == col).toList(),
    );

    final widths =
        layout.columnWidths ??
        List.filled(layout.columnCount, 100.0 / layout.columnCount);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int col = 0; col < layout.columnCount; col++) ...[
          if (col > 0) const SizedBox(width: 16),
          Expanded(
            flex: (widths[col] * 100).round(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final block in columns[col])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: BlockDispatcher(
                      block: block,
                      assetService: assetService,
                      onNextSlide: onNextSlide,
                      presentationMode: presentationMode,
                      isActiveSlide: isActiveSlide,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
