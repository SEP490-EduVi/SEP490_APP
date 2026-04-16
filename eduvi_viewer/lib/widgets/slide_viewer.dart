import 'package:flutter/material.dart';

import '../models/card_model.dart';
import '../services/asset_service.dart';
import 'layout_renderer.dart';

class SlideViewer extends StatelessWidget {
  final EduViCard card;
  final AssetService assetService;
  final VoidCallback? onNextSlide;

  const SlideViewer({
    super.key,
    required this.card,
    required this.assetService,
    this.onNextSlide,
  });

  @override
  Widget build(BuildContext context) {
    final mainAxisAlignment = switch (card.contentAlignment) {
      'top' => MainAxisAlignment.start,
      'bottom' => MainAxisAlignment.end,
      _ => MainAxisAlignment.center,
    };

    DecorationImage? backgroundImage;
    final bgSrc = card.backgroundImage ?? '';
    if (bgSrc.isNotEmpty) {
      final bytes = assetService.resolve(bgSrc);
      if (bytes != null) {
        backgroundImage = DecorationImage(
          image: MemoryImage(bytes),
          fit: BoxFit.cover,
        );
      } else if (bgSrc.startsWith('http')) {
        backgroundImage = DecorationImage(
          image: NetworkImage(bgSrc),
          fit: BoxFit.cover,
        );
      }
    }

    final backgroundColor = _resolveBackgroundColor(card.backgroundColor);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        image: backgroundImage,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.72),
                child: Column(
                  mainAxisAlignment: mainAxisAlignment,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final layout in card.layouts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: LayoutRenderer(
                          layout: layout,
                          assetService: assetService,
                          onNextSlide: onNextSlide,
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

  Color _resolveBackgroundColor(Color? source) {
    if (source == null) return Colors.white;
    final brightness = ThemeData.estimateBrightnessForColor(source);
    // Keep viewer consistent with web slide look: auto-normalize dark imported colors.
    if (brightness == Brightness.dark) return Colors.white;
    return source;
  }
}
