import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/models/block_model.dart';
import 'package:eduvi_viewer/models/card_model.dart';
import 'package:eduvi_viewer/models/layout_model.dart';
import 'package:eduvi_viewer/services/asset_service.dart';
import 'package:eduvi_viewer/widgets/slide_viewer.dart';

void main() {
  testWidgets('slide viewer does not lock content to fixed desktop width', (
    tester,
  ) async {
    final card = EduViCard(
      id: 'card-1',
      title: 'Demo',
      order: 0,
      layouts: [
        EduViLayout(
          id: 'layout-1',
          variant: 'SINGLE',
          order: 0,
          blocks: [
            EduViBlock(
              id: 'block-1',
              type: 'HEADING',
              columnIndex: 0,
              order: 0,
              content: {'text': 'Slide demo'},
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1600,
            height: 900,
            child: SlideViewer(
              card: card,
              assetService: AssetService({}),
            ),
          ),
        ),
      ),
    );

    final fixedWidthConstraint = find.byWidgetPredicate((widget) {
      if (widget is! ConstrainedBox) return false;
      return widget.constraints.maxWidth == 1120;
    });

    expect(fixedWidthConstraint, findsNothing);
  });
}
