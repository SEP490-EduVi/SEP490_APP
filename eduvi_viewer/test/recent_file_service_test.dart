import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduvi_viewer/models/block_model.dart';
import 'package:eduvi_viewer/models/card_model.dart';
import 'package:eduvi_viewer/models/eduvi_schema.dart';
import 'package:eduvi_viewer/models/layout_model.dart';
import 'package:eduvi_viewer/services/recent_file_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  EduViSchema buildSchema({
    String title = 'Bai hoc',
    String gradeCode = 'lop_10',
    String gradeName = 'Lop 10',
    String subjectCode = 'dia_li',
    String subjectName = 'Dia Li',
    String projectCode = 'P001',
    String projectName = 'Dia 10',
  }) {
    return EduViSchema(
      version: '1.1.0',
      exportedAt: '2026-04-14T00:00:00.000Z',
      metadata: EduViMetadata(
        title: title,
        description: 'mo ta',
        createdAt: '2026-04-10T00:00:00.000Z',
        updatedAt: '2026-04-12T00:00:00.000Z',
        projectCode: projectCode,
        projectName: projectName,
        subjectCode: subjectCode,
        subjectName: subjectName,
        gradeCode: gradeCode,
        gradeName: gradeName,
      ),
      cards: [
        EduViCard(
          id: 'card-1',
          title: 'Card 1',
          order: 0,
          isVideoSlide: true,
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
                  content: {'html': '<p>hello</p>'},
                ),
                EduViBlock(
                  id: 'block-2',
                  type: 'QUIZ',
                  columnIndex: 0,
                  order: 1,
                  content: {'questions': []},
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  test('saveLastOpened stores rich history entry', () async {
    final schema = buildSchema();
    await RecentFileService.saveLastOpened(
      filePath: 'D:/tmp/a.eduvi',
      schema: schema,
    );

    final history = await RecentFileService.getHistory();
    expect(history, hasLength(1));

    final first = history.first;
    expect(first.gradeCode, 'lop_10');
    expect(first.gradeName, 'Lop 10');
    expect(first.subjectCode, 'dia_li');
    expect(first.projectCode, 'P001');
    expect(first.slideCount, 1);
    expect(first.hasQuiz, true);
    expect(first.hasVideo, true);
    expect(first.blockTypeCounts['TEXT'], 1);
    expect(first.blockTypeCounts['QUIZ'], 1);
  });

  test('history is trimmed to 200 latest entries', () async {
    for (int i = 0; i < 205; i++) {
      await RecentFileService.saveLastOpened(
        filePath: 'D:/tmp/$i.eduvi',
        schema: buildSchema(title: 'Bai $i', projectCode: 'P$i'),
      );
    }

    final history = await RecentFileService.getHistory();
    expect(history.length, 200);
    expect(history.first.title, 'Bai 204');
    expect(history.last.title, 'Bai 5');
  });

  test('legacy single last-opened payload is migrated to history list', () async {
    final legacy = LastOpenedEduViInfo(
      filePath: 'D:/tmp/legacy.eduvi',
      openedAt: '2026-04-14T08:30:00.000Z',
      title: 'Legacy',
      description: '',
      createdAt: '2026-04-10T00:00:00.000Z',
      updatedAt: '2026-04-12T00:00:00.000Z',
      projectCode: 'P-LEGACY',
      projectName: 'Legacy Project',
      subjectCode: 'su',
      subjectName: 'Lich Su',
      gradeCode: 'lop_11',
      gradeName: 'Lop 11',
    );

    SharedPreferences.setMockInitialValues({
      'last_opened_eduvi': legacy.toJsonString(),
    });

    final history = await RecentFileService.getHistory();
    expect(history, hasLength(1));
    expect(history.first.title, 'Legacy');
    expect(history.first.projectCode, 'P-LEGACY');
  });

  test('saveGameOpened stores game entry with package type', () async {
    await RecentFileService.saveGameOpened(
      filePath: 'D:/tmp/game.eduvi',
      title: 'Game test',
    );

    final history = await RecentFileService.getHistory();
    expect(history, hasLength(1));
    expect(history.first.packageType, 'game');
    expect(history.first.slideCount, 0);
    expect(history.first.title, 'Game test');
  });
}
