import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/models/block_model.dart';
import 'package:eduvi_viewer/models/card_model.dart';
import 'package:eduvi_viewer/models/eduvi_schema.dart';
import 'package:eduvi_viewer/models/layout_model.dart';
import 'package:eduvi_viewer/screens/presentation_screen.dart';

void main() {
  EduViSchema buildSchema() {
    return EduViSchema(
      version: '1.1.0',
      exportedAt: '2026-04-14T00:00:00.000Z',
      metadata: EduViMetadata(title: 'Golden Presentation'),
      cards: [
        for (int i = 0; i < 4; i++)
          EduViCard(
            id: 'card-$i',
            title: 'Card $i',
            order: i,
            layouts: [
              EduViLayout(
                id: 'layout-$i',
                variant: 'SINGLE',
                order: 0,
                blocks: [
                  EduViBlock(
                    id: 'text-$i',
                    type: 'TEXT',
                    columnIndex: 0,
                    order: 0,
                    content: {'html': '<p>Slide $i</p>'},
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  testWidgets('presentation chrome top bar and dots match golden', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      MaterialApp(
        home: PresentationScreen(schema: buildSchema(), initialSlideIndex: 1),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('presentation-mode-root')),
      matchesGoldenFile('goldens/presentation_chrome.png'),
    );
  });
}
