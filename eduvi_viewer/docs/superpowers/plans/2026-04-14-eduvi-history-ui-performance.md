# EduVi History UI and Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a detailed 200-entry history system grouped by grade/subject/project metadata, improve UI polish, and optimize file-open responsiveness.

**Architecture:** Extend local history persistence in `RecentFileService` with structured history entries and analytics fields; add a dedicated `HistoryScreen` with grouped/filterable UX; wire Home screen navigation and improve parse performance with isolate-based decoding.

**Tech Stack:** Flutter, Dart, SharedPreferences, Material 3, flutter_test.

---

### Task 1: Add History Domain + Persistence

**Files:**
- Modify: `lib/services/recent_file_service.dart`
- Test: `test/recent_file_service_test.dart`

- [ ] **Step 1: Write the failing test for saving history entries**

```dart
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

  test('saveLastOpened stores rich history entry', () async {
    final schema = EduViSchema(
      version: '1.0.0',
      exportedAt: '2026-04-14T00:00:00.000Z',
      metadata: EduViMetadata(
        title: 'Bai dia ly',
        description: 'Mo ta',
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
          id: 'c1',
          title: 'Card',
          order: 0,
          layouts: [
            EduViLayout(
              id: 'l1',
              variant: 'SINGLE',
              order: 0,
              blocks: [
                EduViBlock(
                  id: 'b1',
                  type: 'TEXT',
                  columnIndex: 0,
                  order: 0,
                  content: {'html': '<p>a</p>'},
                ),
                EduViBlock(
                  id: 'b2',
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

    await RecentFileService.saveLastOpened(filePath: 'D:/tmp/a.eduvi', schema: schema);

    final history = await RecentFileService.getHistory();
    expect(history, isNotEmpty);
    expect(history.first.gradeCode, 'lop_10');
    expect(history.first.subjectCode, 'dia_li');
    expect(history.first.projectCode, 'P001');
    expect(history.first.slideCount, 1);
    expect(history.first.hasQuiz, true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/recent_file_service_test.dart`
Expected: FAIL because `getHistory` and rich history fields are not implemented yet.

- [ ] **Step 3: Implement history model, migration, trim-to-200, and analytics extraction**

```dart
// In RecentFileService:
// - Add EduViHistoryEntry model with toJson/fromJson
// - Add getHistory(), removeHistoryEntry(), clearHistory()
// - In saveLastOpened(), append entry then trim to 200
// - Add lazy migration from last_opened_eduvi to eduvi_open_history_v2
// - Extract slideCount, blockTypeCounts, hasVideo, hasQuiz from schema
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/recent_file_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/recent_file_service.dart test/recent_file_service_test.dart
git commit -m "feat: add detailed eduvi open history persistence"
```

### Task 2: Build Grouped and Filterable History Screen

**Files:**
- Create: `lib/screens/history_screen.dart`
- Modify: `lib/screens/home_screen.dart`
- Test: `test/history_screen_test.dart`

- [ ] **Step 1: Write failing widget test for grouped history rendering**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history screen renders group headers', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(find.text('Lich su mo file'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails meaningfully**

Run: `flutter test test/history_screen_test.dart`
Expected: FAIL after replacing placeholder with real `HistoryScreen` expectations.

- [ ] **Step 3: Implement HistoryScreen with grouping + filters + item actions**

```dart
// Create HistoryScreen with:
// - Search field
// - Grade/Subject/Project dropdown filters
// - hasVideo/hasQuiz chips
// - Grouped ExpansionTiles: grade -> subject -> project
// - Item cards showing metadata, path, slide count, block chips
// - Reopen action and remove action
```

- [ ] **Step 4: Wire HomeScreen button to HistoryScreen**

```dart
// Add secondary action on HomeScreen:
// OutlinedButton.icon(
//   onPressed: _openHistory,
//   icon: Icon(Icons.history),
//   label: Text('Lich su'),
// )
```

- [ ] **Step 5: Run widget test and smoke test**

Run: `flutter test test/history_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/home_screen.dart lib/screens/history_screen.dart test/history_screen_test.dart
git commit -m "feat: add grouped history screen with filters and reopen actions"
```

### Task 3: UI Polish + Parse Performance Optimization

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Modify: `lib/services/file_service.dart`

- [ ] **Step 1: Write failing test for parse function behavior**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:eduvi_viewer/services/file_service.dart';

void main() {
  test('schema parse helper handles minimal json', () {
    final jsonText = jsonEncode({
      'version': '1.0.0',
      'exportedAt': '',
      'metadata': {'title': 'T'},
      'cards': [],
      'assets': {},
    });

    final schema = FileService.parseSchemaJson(jsonText);
    expect(schema.metadata.title, 'T');
  });
}
```

- [ ] **Step 2: Run test to verify fail**

Run: `flutter test test/file_service_test.dart`
Expected: FAIL because `parseSchemaJson` helper does not exist.

- [ ] **Step 3: Implement isolate-friendly parser and UI polish**

```dart
// In FileService:
// - add static parseSchemaJson(String jsonString)
// - parseFile reads file string and uses compute(...) helper

// In AppTheme:
// - refine colors, input styles, button styles, chips/cards for premium look
```

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/file_service.dart lib/theme/app_theme.dart test/file_service_test.dart
git commit -m "perf: parse eduvi on isolate and polish theme"
```

### Task 4: End-to-End Verification

**Files:**
- Modify if needed: `lib/screens/history_screen.dart`, `lib/services/recent_file_service.dart`, `lib/screens/home_screen.dart`

- [ ] **Step 1: Run analyzer**

Run: `flutter analyze`
Expected: no new analyzer errors introduced by this work.

- [ ] **Step 2: Run tests**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 3: Manual smoke checks**

Run app and verify:
- import `.eduvi`
- history grows and caps at 200
- grouped sections by grade/subject/project are correct
- filters/search narrow results
- reopen works for existing file path

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "feat: complete eduvi history grouping, ui polish, and performance updates"
```
