import 'package:flutter/material.dart';

import '../models/card_model.dart';
import '../services/asset_service.dart';
import 'layout_renderer.dart';

class SlideViewer extends StatelessWidget {
  final EduViCard card;
  final AssetService assetService;
  final VoidCallback? onNextSlide;
  final bool presentationMode;
  final bool isActiveSlide;
  final bool allowUserInteraction;

  const SlideViewer({
    super.key,
    required this.card,
    required this.assetService,
    this.onNextSlide,
    this.presentationMode = false,
    this.isActiveSlide = true,
    this.allowUserInteraction = true,
  });

  @override
  Widget build(BuildContext context) {
    final mainAxisAlignment = switch (card.contentAlignment.toLowerCase()) {
      'bottom' => MainAxisAlignment.end,
      _ => MainAxisAlignment.start,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final outerPadding = EdgeInsets.symmetric(
          horizontal: constraints.maxWidth > 1200 ? 18 : 10,
          vertical: 10,
        );

        final innerPadding = EdgeInsets.symmetric(
          horizontal: constraints.maxWidth > 1000 ? 24 : 14,
          vertical: 16,
        );

        return Padding(
          padding: outerPadding,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              image: backgroundImage,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD6E1EE)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (presentationMode && !allowUserInteraction)
                  ? SelectionContainer.disabled(
                      child: SingleChildScrollView(
                        padding: innerPadding,
                        child: Column(
                          mainAxisAlignment: mainAxisAlignment,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final layout in card.layouts)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: LayoutRenderer(
                                  layout: layout,
                                  assetService: assetService,
                                  onNextSlide: onNextSlide,
                                  presentationMode: presentationMode,
                                  isActiveSlide: isActiveSlide,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: innerPadding,
                      child: Column(
                        mainAxisAlignment: mainAxisAlignment,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final layout in card.layouts)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: LayoutRenderer(
                                layout: layout,
                                assetService: assetService,
                                onNextSlide: onNextSlide,
                                presentationMode: presentationMode,
                                isActiveSlide: isActiveSlide,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
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
