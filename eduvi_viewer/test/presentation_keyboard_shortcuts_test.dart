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
          title: 'Intro',
          order: 0,
          layouts: [
            EduViLayout(
              id: 'layout-1',
              variant: 'SINGLE',
              order: 0,
              blocks: [
                EduViBlock(
                  id: 'text-1',
                  type: 'TEXT',
                  columnIndex: 0,
                  order: 0,
                  content: {'html': '<p>Trang 1</p>'},
                ),
              ],
            ),
          ],
        ),
        EduViCard(
          id: 'card-2',
          title: 'Quiz',
          order: 1,
          layouts: [
            EduViLayout(
              id: 'layout-2',
              variant: 'SINGLE',
              order: 0,
              blocks: [
                EduViBlock(
                  id: 'quiz-1',
                  type: 'QUIZ',
                  columnIndex: 0,
                  order: 0,
                  content: {
                    'questions': [
                      {
                        'question': '2 + 2 = ?',
                        'correctIndex': 1,
                        'options': [
                          {'text': '3'},
                          {'text': '4'},
                        ],
                      },
                    ],
                  },
                ),
              ],
            ),
          ],
        ),
        EduViCard(
          id: 'card-3',
          title: 'Outro',
          order: 2,
          layouts: [
            EduViLayout(
              id: 'layout-3',
              variant: 'SINGLE',
              order: 0,
              blocks: [
                EduViBlock(
                  id: 'text-3',
                  type: 'TEXT',
                  columnIndex: 0,
                  order: 0,
                  content: {'html': '<p>Trang 3</p>'},
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> pumpPresentation(
    WidgetTester tester, {
    int initialSlide = 0,
    ValueChanged<int>? onExit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PresentationScreen(
          schema: buildSchema(),
          initialSlideIndex: initialSlide,
          onExitSlideChanged: onExit,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PageController readController(WidgetTester tester) {
    final pageView = tester.widget<PageView>(find.byType(PageView));
    return pageView.controller!;
  }

  testWidgets('keyboard arrows navigate next and previous with web mapping', (
    tester,
  ) async {
    await pumpPresentation(tester);

    final controller = readController(tester);
    expect(controller.page, 0);
    expect(find.text('1/3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    expect(find.text('2/3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.page, 2);
    expect(find.text('3/3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(controller.page, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(controller.page, 0);
  });

  testWidgets('goToSlide via dot indicator moves to selected slide', (
    tester,
  ) async {
    await pumpPresentation(tester);

    await tester.tap(find.byKey(const Key('presentation-dot-2')));
    await tester.pumpAndSettle();

    final controller = readController(tester);
    expect(controller.page, 2);
    expect(find.text('3/3'), findsOneWidget);
  });

  testWidgets('startPresentation starts from active slide index', (
    tester,
  ) async {
    await pumpPresentation(tester, initialSlide: 1);

    final controller = readController(tester);
    expect(controller.page, 1);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets(
    'space navigates on non-interactive slide but is blocked on interactive slide',
    (tester) async {
      await pumpPresentation(tester);

      final controller = readController(tester);
      expect(controller.page, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.page, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
    },
  );

  testWidgets('exitPresentation returns current slide on escape', (
    tester,
  ) async {
    int? callbackSlide;
    int? poppedSlide;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context)
                        .push<int>(
                          MaterialPageRoute(
                            builder: (_) => PresentationScreen(
                              schema: buildSchema(),
                              onExitSlideChanged: (slide) {
                                callbackSlide = slide;
                              },
                            ),
                          ),
                        )
                        .then((value) => poppedSlide = value);
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(PresentationScreen), findsNothing);
    expect(callbackSlide, 1);
    expect(poppedSlide, 1);
  });
}
