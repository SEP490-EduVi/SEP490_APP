import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduvi_viewer/models/block_model.dart';
import 'package:eduvi_viewer/models/card_model.dart';
import 'package:eduvi_viewer/models/eduvi_schema.dart';
import 'package:eduvi_viewer/models/layout_model.dart';
import 'package:eduvi_viewer/screens/history_screen.dart';
import 'package:eduvi_viewer/services/recent_file_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  EduViSchema buildSchema() {
    return EduViSchema(
      version: '1.1.0',
      exportedAt: '2026-04-14T00:00:00.000Z',
      metadata: EduViMetadata(
        title: 'Địa lí 10',
        description: 'mô tả',
        createdAt: '2026-04-10T00:00:00.000Z',
        updatedAt: '2026-04-12T00:00:00.000Z',
        projectCode: 'P-MNID2JDTS64',
        projectName: 'Địa 10',
        subjectCode: 'dia_li',
        subjectName: 'Địa Lí',
        gradeCode: 'lop_10',
        gradeName: 'Lớp 10',
      ),
      cards: [
        EduViCard(
          id: 'card-1',
          title: 'Card 1',
          order: 0,
          layouts: [
            EduViLayout(
              id: 'layout-1',
              variant: 'SINGLE',
              order: 0,
              blocks: [
                EduViBlock(
                  id: 'block-1',
                  type: 'TEXT',
                  columnIndex: 0,
                  order: 0,
                  content: {'html': '<p>abc</p>'},
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('history screen renders Vietnamese labels with diacritics', (tester) async {
    await RecentFileService.saveLastOpened(
      filePath: 'D:/tmp/a.eduvi',
      schema: buildSchema(),
    );

    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Lịch sử mở file'), findsOneWidget);
    expect(find.textContaining('Lớp 10'), findsWidgets);
    expect(find.textContaining('Địa Lí'), findsWidgets);
    expect(find.textContaining('Địa 10'), findsWidgets);
    expect(find.text('Khối'), findsOneWidget);
    expect(find.text('Môn'), findsOneWidget);
  });

  testWidgets('history screen avoids hardcoded light-only background colors in dark mode', (
    tester,
  ) async {
    await RecentFileService.saveLastOpened(
      filePath: 'D:/tmp/a.eduvi',
      schema: buildSchema(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.dark,
        home: const HistoryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final containers = tester.widgetList<Container>(find.byType(Container));
    final hasHardcodedLightSurface = containers.any((container) {
      final decoration = container.decoration;
      if (decoration is! BoxDecoration) return false;

      if (decoration.color == const Color(0xFFF8FAFC)) {
        return true;
      }

      final gradient = decoration.gradient;
      if (gradient is LinearGradient) {
        return gradient.colors.any(
          (color) => color == const Color(0xFFF3FAFF) || color == const Color(0xFFF8FAFC),
        );
      }

      return false;
    });

    expect(hasHardcodedLightSurface, isFalse);
  });
}
