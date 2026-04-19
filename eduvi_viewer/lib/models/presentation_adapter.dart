import 'block_model.dart';
import 'card_model.dart';
import 'eduvi_schema.dart';

extension PresentationSchemaAdapter on EduViSchema {
  int clampSlideIndex(int index) {
    if (cards.isEmpty) return 0;
    if (index < 0) return 0;
    if (index >= cards.length) return cards.length - 1;
    return index;
  }

  EduViCard? slideAt(int index) {
    if (index < 0 || index >= cards.length) return null;
    return cards[index];
  }
}

extension PresentationCardAdapter on EduViCard {
  Iterable<EduViBlock> get allBlocks sync* {
    for (final layout in layouts) {
      for (final block in layout.blocks) {
        yield block;
      }
    }
  }

  bool get hasLearningInteractiveBlocks =>
      allBlocks.any((block) => block.isLearningInteractiveBlock);

  bool get hasUserInteractiveBlocks =>
      allBlocks.any((block) => block.isUserInteractiveBlock);
}

extension PresentationBlockAdapter on EduViBlock {
  bool get isLearningInteractiveBlock {
    final normalizedType = type.toUpperCase();
    if (normalizedType == 'QUIZ' ||
        normalizedType == 'FLASHCARD' ||
        normalizedType == 'FILL_BLANK') {
      return true;
    }

    if (normalizedType == 'MATERIAL') {
      final widgetType = (content['widgetType'] as String? ?? '').toUpperCase();
      if (widgetType == 'MATERIAL_QUIZ') return true;
    }

    return false;
  }

  bool get isMediaInteractiveBlock {
    final normalizedType = type.toUpperCase();
    if (normalizedType == 'VIDEO') return true;

    if (normalizedType == 'MATERIAL') {
      final widgetType = (content['widgetType'] as String? ?? '').toUpperCase();
      if (widgetType == 'MATERIAL_VIDEO' || widgetType == 'MATERIAL_YOUTUBE') {
        return true;
      }
    }

    return false;
  }

  bool get isUserInteractiveBlock =>
      isLearningInteractiveBlock || isMediaInteractiveBlock;
}
