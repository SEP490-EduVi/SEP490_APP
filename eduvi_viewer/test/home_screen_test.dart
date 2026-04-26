import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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

  testWidgets(
    'home screen shows history immediately without opening history page',
    (tester) async {
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
    },
  );

  testWidgets(
    'home screen shows desktop concept sections with sidebar and recent list',
    (tester) async {
      await RecentFileService.saveLastOpened(
        filePath: 'D:/tmp/c.eduvi',
        schema: buildSchema(title: 'Bai concept'),
      );

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-sidebar-logo')), findsOneWidget);
      expect(find.text('Trang chủ'), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsNothing);
      expect(find.text('Mở file'), findsOneWidget);
      expect(find.text('Làm mới'), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.text('Lịch sử gần đây'), findsOneWidget);
      expect(find.text('Bai concept'), findsOneWidget);
    },
  );

  testWidgets('home history list renders video package entry', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final openedVideo = now.toIso8601String();
    final openedGame = now.subtract(const Duration(minutes: 1)).toIso8601String();
    final payload = jsonEncode([
      {
        'id': 'video-1',
        'filePath': 'D:/tmp/video.eduvi',
        'openedAt': openedVideo,
        'title': 'Video item',
        'description': '',
        'createdAt': openedVideo,
        'updatedAt': openedVideo,
        'slideCount': 0,
        'blockTypeCounts': {},
        'hasVideo': true,
        'hasQuiz': true,
        'packageType': 'video',
      },
      {
        'id': 'game-1',
        'filePath': 'D:/tmp/game.eduvi',
        'openedAt': openedGame,
        'title': 'Game item',
        'description': '',
        'createdAt': openedGame,
        'updatedAt': openedGame,
        'slideCount': 0,
        'blockTypeCounts': {},
        'hasVideo': false,
        'hasQuiz': false,
        'packageType': 'game',
      },
    ]);

    SharedPreferences.setMockInitialValues({
      'eduvi_open_history_v2': payload,
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Video item'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
  });

  testWidgets('home history list normalizes legacy technical game title', (
    tester,
  ) async {
    final now = DateTime.now().toIso8601String();
    final payload = jsonEncode([
      {
        'id': 'game-legacy-1',
        'filePath': 'C:/Users/nguye/Downloads/bai-1-game-20260420-141726.eduvi',
        'openedAt': now,
        'title': 'Game b_i_1',
        'description': '',
        'createdAt': now,
        'updatedAt': now,
        'slideCount': 0,
        'blockTypeCounts': {},
        'hasVideo': false,
        'hasQuiz': false,
        'packageType': 'game',
      },
    ]);

    SharedPreferences.setMockInitialValues({
      'eduvi_open_history_v2': payload,
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('bai-1-game-20260420-141726'), findsOneWidget);
    expect(find.text('Game b_i_1'), findsNothing);
  });

  testWidgets('home history list normalizes legacy technical game title', (
    tester,
  ) async {
    final now = DateTime.now().toIso8601String();
    final payload = jsonEncode([
      {
        'id': 'game-legacy-1',
        'filePath': 'C:/Users/nguye/Downloads/bai-1-game-20260420-141726.eduvi',
        'openedAt': now,
        'title': 'Game b_i_1',
        'description': '',
        'createdAt': now,
        'updatedAt': now,
        'slideCount': 0,
        'blockTypeCounts': {},
        'hasVideo': false,
        'hasQuiz': false,
        'packageType': 'game',
      },
    ]);

    SharedPreferences.setMockInitialValues({
      'eduvi_open_history_v2': payload,
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('bai-1-game-20260420-141726'), findsOneWidget);
    expect(find.text('Game b_i_1'), findsNothing);
  });
}
