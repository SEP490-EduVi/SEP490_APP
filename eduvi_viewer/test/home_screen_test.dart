import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduvi_viewer/models/block_model.dart';
import 'package:eduvi_viewer/models/card_model.dart';
import 'package:eduvi_viewer/models/eduvi_schema.dart';
import 'package:eduvi_viewer/models/layout_model.dart';
import 'package:eduvi_viewer/screens/home_screen.dart';
import 'package:eduvi_viewer/services/recent_file_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  EduViSchema buildSchema({required String title}) {
    return EduViSchema(
      version: '1.1.0',
      exportedAt: '2026-04-14T00:00:00.000Z',
      metadata: EduViMetadata(
        title: title,
        description: 'mo ta',
        createdAt: '2026-04-10T00:00:00.000Z',
        updatedAt: '2026-04-12T00:00:00.000Z',
        projectCode: 'P001',
        projectName: 'Dia 10',
        subjectCode: 'dia_li',
        subjectName: 'Dia Li',
        gradeCode: 'lop_10',
        gradeName: 'Lop 10',
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

  testWidgets('home screen shows history immediately without opening history page', (
    tester,
  ) async {
    await RecentFileService.saveLastOpened(
      filePath: 'D:/tmp/a.eduvi',
      schema: buildSchema(title: 'Bai 1'),
    );
    await RecentFileService.saveLastOpened(
      filePath: 'D:/tmp/b.eduvi',
      schema: buildSchema(title: 'Bai 2'),
    );

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Lịch sử gần đây'), findsOneWidget);
    expect(find.text('Bai 2'), findsOneWidget);
    expect(find.text('Bai 1'), findsOneWidget);
    expect(find.text('Xem lịch sử'), findsNothing);
  });

  testWidgets('home screen shows desktop concept sections with sidebar and recent list', (
    tester,
  ) async {
    await RecentFileService.saveLastOpened(
      filePath: 'D:/tmp/c.eduvi',
      schema: buildSchema(title: 'Bai concept'),
    );

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Trang chủ'), findsWidgets);
    expect(find.text('Mở file'), findsOneWidget);
    expect(find.text('Lịch sử gần đây'), findsOneWidget);
    expect(find.text('Bai concept'), findsOneWidget);
  });
}
