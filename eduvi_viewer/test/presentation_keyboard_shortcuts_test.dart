import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      metadata: EduViMetadata(title: 'Keyboard test'),
      cards: [
        EduViCard(
          id: 'card-1',
          title: 'Fill blank',
          order: 0,
          layouts: [
            EduViLayout(
              id: 'layout-1',
              variant: 'SINGLE',
              order: 0,
              blocks: [
                EduViBlock(
                  id: 'fill-1',
                  type: 'FILL_BLANK',
                  columnIndex: 0,
                  order: 0,
                  content: {
                    'sentence': 'Từ khóa là [blank_1].',
                    'blanks': ['dữ liệu lớn'],
                  },
                ),
              ],
            ),
          ],
        ),
        EduViCard(
          id: 'card-2',
          title: 'Second slide',
          order: 1,
          layouts: [
            EduViLayout(
              id: 'layout-2',
              variant: 'SINGLE',
              order: 0,
              blocks: [
                EduViBlock(
                  id: 'text-1',
                  type: 'TEXT',
                  columnIndex: 0,
                  order: 0,
                  content: {'html': '<p>Trang 2</p>'},
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('space key does not navigate slide while typing in fill blank input', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: PresentationScreen(schema: buildSchema())));
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    final controller = pageView.controller!;
    expect(controller.page, 0);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(controller.page, 0);
  });
}
