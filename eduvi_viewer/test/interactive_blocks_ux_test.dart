import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/models/block_model.dart';
import 'package:eduvi_viewer/widgets/blocks/fill_blank_block_widget.dart';
import 'package:eduvi_viewer/widgets/blocks/quiz_block_widget.dart';

void main() {
  EduViBlock buildFillBlankBlock() {
    return EduViBlock(
      id: 'fill-1',
      type: 'FILL_BLANK',
      columnIndex: 0,
      order: 0,
      content: {
        'sentence': 'Thủ đô của Việt Nam là [blank_1].',
        'blanks': ['Hà Nội'],
      },
    );
  }

  EduViBlock buildSingleQuestionQuiz() {
    return EduViBlock(
      id: 'quiz-1',
      type: 'QUIZ',
      columnIndex: 0,
      order: 0,
      content: {
        'questions': [
          {
            'question': '2 + 2 bằng mấy?',
            'correctIndex': 1,
            'options': [
              {'text': '3'},
              {'text': '4'},
            ],
          },
        ],
      },
    );
  }

  testWidgets('fill blank supports click to view answers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FillBlankBlockWidget(block: buildFillBlankBlock()),
        ),
      ),
    );

    expect(find.text('Xem đáp án'), findsOneWidget);

    await tester.tap(find.text('Xem đáp án'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hà Nội'), findsWidgets);
  });

  testWidgets('fill blank accepts Vietnamese tone placement variants', (
    tester,
  ) async {
    final block = EduViBlock(
      id: 'fill-variant',
      type: 'FILL_BLANK',
      columnIndex: 0,
      order: 0,
      content: {
        'sentence': '[blank_1] là khái niệm quan trọng.',
        'blanks': ['Từ khoá'],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FillBlankBlockWidget(block: block),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'từ khóa');
    await tester.tap(find.text('Kiểm tra'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 1 đúng'), findsOneWidget);
  });

  testWidgets('quiz uses next-page action instead of result action', (tester) async {
    var movedToNextPage = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuizBlockWidget(
            block: buildSingleQuestionQuiz(),
            onGoNextSlide: () => movedToNextPage = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();

    expect(find.text('Qua trang sau'), findsOneWidget);
    expect(find.text('Xem kết quả'), findsNothing);

    await tester.tap(find.text('Qua trang sau'));
    await tester.pumpAndSettle();

    expect(movedToNextPage, isTrue);
  });
}
