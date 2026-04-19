# EduVi Desktop Viewer — Flutter Implementation Guide

Hướng dẫn xây dựng Flutter Desktop App để import và trình chiếu file `.eduvi`.

---

## Mục lục

1. [Yêu cầu hệ thống](#1-yêu-cầu-hệ-thống)
2. [Khởi tạo project](#2-khởi-tạo-project)
3. [Cài đặt dependencies](#3-cài-đặt-dependencies)
4. [Cấu hình cửa sổ Windows](#4-cấu-hình-cửa-sổ-windows)
5. [.eduvi File Schema](#5-eduvi-file-schema)
6. [Tạo Data Models (Dart)](#6-tạo-data-models-dart)
7. [Service: Import & Parse file](#7-service-import--parse-file)
8. [Service: Asset Resolver](#8-service-asset-resolver)
9. [Màn hình Home](#9-màn-hình-home)
10. [Slide Viewer & Navigation](#10-slide-viewer--navigation)
11. [Layout Renderer (Columns)](#11-layout-renderer-columns)
12. [Block Renderers](#12-block-renderers)
13. [Interactive Blocks (Quiz, Flashcard, Fill-blank)](#13-interactive-blocks)
14. [Slide Transitions & Animations](#14-slide-transitions--animations)
15. [Build & Release](#15-build--release)
16. [Cấu trúc thư mục hoàn chỉnh](#16-cấu-trúc-thư-mục-hoàn-chỉnh)

---

## 1. Yêu cầu hệ thống

| Tool | Version | Ghi chú |
|------|---------|---------|
| Flutter SDK | >= 3.22 | `flutter channel stable` |
| Dart | >= 3.4 | Đi kèm Flutter |
| Visual Studio 2022 | Desktop C++ workload | Bắt buộc cho Windows build |
| Git | any | |

Kiểm tra:

```bash
flutter doctor
flutter config --enable-windows-desktop   # nếu chưa bật
```

---

## 2. Khởi tạo project

```bash
flutter create --platforms=windows,macos,linux --org=com.eduvi eduvi_viewer
cd eduvi_viewer
flutter run -d windows   # test chạy thử
```

---

## 3. Cài đặt dependencies

Thêm vào `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.6.1

  # JSON serialization
  json_annotation: ^4.9.0
  
  # File picker (mở file .eduvi)
  file_picker: ^8.1.6
  
  # HTML rendering (cho text blocks từ Tiptap editor)
  flutter_widget_from_html: ^0.15.2
  
  # Video player (desktop-compatible)
  media_kit: ^1.1.11
  media_kit_video: ^1.2.5
  media_kit_libs_windows_video: ^1.0.10   # Windows only
  # media_kit_libs_macos_video: ^1.1.4    # macOS
  # media_kit_libs_linux: ^1.1.3          # Linux
  
  # Window management
  window_manager: ^0.4.3
  
  # Drag-and-drop
  desktop_drop: ^0.5.0
  
  # Path utilities
  path: ^1.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.13
  json_serializable: ^6.8.0
  flutter_lints: ^5.0.0
```

Sau đó:

```bash
flutter pub get
```

---

## 4. Cấu hình cửa sổ Windows

Trong `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Cấu hình cửa sổ
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(800, 600),
    center: true,
    title: 'EduVi Viewer',
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: EduViApp()));
}

class EduViApp extends StatelessWidget {
  const EduViApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EduVi Viewer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
```

---

## 5. .eduvi File Schema

File `.eduvi` là JSON với cấu trúc sau (schema version `1.1.0`):

```
EduViFileSchema
├── version: "1.1.0"
├── exportedAt: "2026-04-09T10:00:00.000Z"
├── metadata
│   ├── title: string
│   ├── description: string
│   ├── createdAt: string (ISO 8601)
│   └── updatedAt: string (ISO 8601)
├── cards[]:                          ← Mỗi card = 1 slide
│   ├── id, title, order
│   ├── backgroundColor?: "#1e293b"   ← CSS hex color
│   ├── backgroundImage?: "asset://asset-2"
│   ├── contentAlignment?: "top" | "center" | "bottom"
│   ├── isVideoSlide?: boolean
│   └── layouts[]:                    ← Containers cho blocks
│       ├── id, variant, order
│       ├── columnWidths?: [50, 50]   ← Phần trăm, tổng = 100
│       └── blocks[]:                 ← Nội dung thực tế
│           ├── id, type, columnIndex, order
│           ├── styles?: { width, height, maxWidth, aspectRatio... }
│           └── content: (xem bảng dưới)
├── assets?:                          ← Media nhúng base64
│   └── "asset-1": { mimeType, base64, originalUrl, kind }
└── integrity?:
    ├── warnings: string[]
    └── stats: { totalCards, totalBlocks, blocksByType, ... }
```

### Block content theo type

| type | content fields | Ví dụ |
|------|---------------|-------|
| `TEXT` | `html: string` | `<p>Xin chào <strong>thế giới</strong></p>` |
| `HEADING` | `html: string, level: 1-6` | `<h2>Tiêu đề</h2>` |
| `IMAGE` | `src, alt?, caption?, missingMedia?` | `src: "asset://asset-2"` hoặc `src: ""` + `missingMedia: true` |
| `VIDEO` | `src, provider?, missingMedia?` | `src: "asset://asset-1"`, `provider: "direct"` |
| `QUIZ` | `title, questions[]` | Mỗi question: `{ id, question, options[], correctIndex, explanation? }` |
| `FLASHCARD` | `front: string, back: string` | HTML cả hai mặt |
| `FILL_BLANK` | `sentence, blanks[]` | `"Java là ngôn ngữ [lập trình]"` → blanks: `["lập trình"]` |

### Layout variants

| variant | Cột | columnWidths mặc định |
|---------|-----|-----------------------|
| `SINGLE` | 1 | không có |
| `TWO_COLUMN` | 2 | `[50, 50]` |
| `THREE_COLUMN` | 3 | `[33.33, 33.33, 33.34]` |
| `SIDEBAR_LEFT` | 2 | `[33, 67]` |
| `SIDEBAR_RIGHT` | 2 | `[67, 33]` |

### Asset resolution

Khi block content có `src: "asset://asset-1"`:
1. Tìm key `"asset-1"` trong `schema.assets`
2. Decode `base64` field → `Uint8List`
3. Render bằng `Image.memory()` hoặc `media_kit` from memory

---

## 6. Tạo Data Models (Dart)

### `lib/models/eduvi_schema.dart`

```dart
import 'dart:convert';
import 'dart:typed_data';

/// Root schema matching .eduvi JSON
class EduViSchema {
  final String version;
  final String exportedAt;
  final EduViMetadata metadata;
  final List<EduViCard> cards;
  final Map<String, EduViAsset> assets;

  EduViSchema({
    required this.version,
    required this.exportedAt,
    required this.metadata,
    required this.cards,
    this.assets = const {},
  });

  factory EduViSchema.fromJson(Map<String, dynamic> json) {
    return EduViSchema(
      version: json['version'] as String? ?? '1.0.0',
      exportedAt: json['exportedAt'] as String? ?? '',
      metadata: EduViMetadata.fromJson(json['metadata'] as Map<String, dynamic>? ?? {}),
      cards: (json['cards'] as List<dynamic>? ?? [])
          .map((c) => EduViCard.fromJson(c as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      assets: (json['assets'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, EduViAsset.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}

class EduViMetadata {
  final String title;
  final String description;

  EduViMetadata({required this.title, this.description = ''});

  factory EduViMetadata.fromJson(Map<String, dynamic> json) {
    return EduViMetadata(
      title: json['title'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
    );
  }
}

class EduViAsset {
  final String mimeType;
  final String base64Data;
  final String originalUrl;
  final String kind;

  EduViAsset({
    required this.mimeType,
    required this.base64Data,
    required this.originalUrl,
    required this.kind,
  });

  /// Decoded bytes — cache lại sau lần đầu
  Uint8List get bytes => base64Decode(base64Data);

  factory EduViAsset.fromJson(Map<String, dynamic> json) {
    return EduViAsset(
      mimeType: json['mimeType'] as String? ?? '',
      base64Data: json['base64'] as String? ?? '',
      originalUrl: json['originalUrl'] as String? ?? '',
      kind: json['kind'] as String? ?? 'generic',
    );
  }
}
```

### `lib/models/card_model.dart`

```dart
import 'package:flutter/material.dart';

class EduViCard {
  final String id;
  final String title;
  final int order;
  final Color? backgroundColor;
  final String? backgroundImage;
  final String contentAlignment; // 'top' | 'center' | 'bottom'
  final bool isVideoSlide;
  final List<EduViLayout> layouts;

  EduViCard({
    required this.id,
    required this.title,
    required this.order,
    this.backgroundColor,
    this.backgroundImage,
    this.contentAlignment = 'center',
    this.isVideoSlide = false,
    required this.layouts,
  });

  factory EduViCard.fromJson(Map<String, dynamic> json) {
    return EduViCard(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      backgroundColor: _parseColor(json['backgroundColor'] as String?),
      backgroundImage: json['backgroundImage'] as String?,
      contentAlignment: json['contentAlignment'] as String? ?? 'center',
      isVideoSlide: json['isVideoSlide'] as bool? ?? false,
      layouts: (json['layouts'] as List<dynamic>? ?? [])
          .map((l) => EduViLayout.fromJson(l as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    if (cleaned.length == 8) {
      return Color(int.parse(cleaned, radix: 16));
    }
    return null;
  }
}
```

### `lib/models/layout_model.dart`

```dart
class EduViLayout {
  final String id;
  final String variant;
  final int order;
  final List<double>? columnWidths;
  final List<EduViBlock> blocks;

  EduViLayout({
    required this.id,
    required this.variant,
    required this.order,
    this.columnWidths,
    required this.blocks,
  });

  int get columnCount {
    switch (variant) {
      case 'TWO_COLUMN':
      case 'SIDEBAR_LEFT':
      case 'SIDEBAR_RIGHT':
        return 2;
      case 'THREE_COLUMN':
        return 3;
      default:
        return 1;
    }
  }

  factory EduViLayout.fromJson(Map<String, dynamic> json) {
    return EduViLayout(
      id: json['id'] as String,
      variant: json['variant'] as String? ?? 'SINGLE',
      order: json['order'] as int? ?? 0,
      columnWidths: (json['columnWidths'] as List<dynamic>?)
          ?.map((v) => (v as num).toDouble())
          .toList(),
      blocks: (json['blocks'] as List<dynamic>? ?? [])
          .map((b) => EduViBlock.fromJson(b as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }
}
```

### `lib/models/block_model.dart`

```dart
class EduViBlock {
  final String id;
  final String type; // TEXT, HEADING, IMAGE, VIDEO, QUIZ, FLASHCARD, FILL_BLANK
  final int columnIndex;
  final int order;
  final Map<String, dynamic>? styles;
  final Map<String, dynamic> content;

  EduViBlock({
    required this.id,
    required this.type,
    required this.columnIndex,
    required this.order,
    this.styles,
    required this.content,
  });

  /// Quick accessors
  String get html => content['html'] as String? ?? '';
  String get src => content['src'] as String? ?? '';
  String get alt => content['alt'] as String? ?? '';
  int get headingLevel => content['level'] as int? ?? 2;
  bool get missingMedia => content['missingMedia'] as bool? ?? false;
  String get provider => content['provider'] as String? ?? 'direct';

  factory EduViBlock.fromJson(Map<String, dynamic> json) {
    return EduViBlock(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'TEXT',
      columnIndex: json['columnIndex'] as int? ?? 0,
      order: json['order'] as int? ?? 0,
      styles: json['styles'] as Map<String, dynamic>?,
      content: json['content'] as Map<String, dynamic>? ?? {},
    );
  }
}
```

> **Tip**: Nếu muốn dùng `json_serializable` cho type-safe hơn, chạy `dart run build_runner build`. Nhưng manual `fromJson` ở trên đủ dùng và dễ debug hơn.

---

## 7. Service: Import & Parse file

### `lib/services/file_service.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../models/eduvi_schema.dart';

class FileService {
  /// Mở file picker, trả về EduViSchema hoặc null
  static Future<EduViSchema?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['eduvi'],
      dialogTitle: 'Chọn file .eduvi',
    );

    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) return null;

    return parseFile(path);
  }

  /// Parse file .eduvi từ đường dẫn
  static Future<EduViSchema> parseFile(String filePath) async {
    final file = File(filePath);
    final jsonString = await file.readAsString(encoding: utf8);
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return EduViSchema.fromJson(json);
  }
}
```

---

## 8. Service: Asset Resolver

### `lib/services/asset_service.dart`

```dart
import 'dart:typed_data';
import '../models/eduvi_schema.dart';

class AssetService {
  final Map<String, EduViAsset> _assets;

  /// Cache decoded bytes để tránh decode base64 nhiều lần
  final Map<String, Uint8List> _bytesCache = {};

  AssetService(this._assets);

  /// Resolve "asset://asset-1" → Uint8List bytes
  Uint8List? resolve(String src) {
    if (!src.startsWith('asset://')) return null;

    final assetId = src.replaceFirst('asset://', '');
    if (_bytesCache.containsKey(assetId)) return _bytesCache[assetId];

    final asset = _assets[assetId];
    if (asset == null || asset.base64Data.isEmpty) return null;

    final bytes = asset.bytes;
    _bytesCache[assetId] = bytes;
    return bytes;
  }

  /// Lấy mime type
  String? getMimeType(String src) {
    if (!src.startsWith('asset://')) return null;
    final assetId = src.replaceFirst('asset://', '');
    return _assets[assetId]?.mimeType;
  }

  /// Check xem asset có phải video không
  bool isVideo(String src) {
    final mime = getMimeType(src) ?? '';
    return mime.startsWith('video/');
  }
}
```

---

## 9. Màn hình Home

### `lib/screens/home_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../services/file_service.dart';
import 'presentation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _dragging = false;
  bool _loading = false;

  Future<void> _openFile([String? path]) async {
    setState(() => _loading = true);
    try {
      final schema = path != null
          ? await FileService.parseFile(path)
          : await FileService.pickAndParse();

      if (schema != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PresentationScreen(schema: schema),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          final files = details.files;
          if (files.isNotEmpty && files.first.path.endsWith('.eduvi')) {
            _openFile(files.first.path);
          }
        },
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(60),
            decoration: BoxDecoration(
              border: Border.all(
                color: _dragging ? Colors.blue : Colors.grey.shade300,
                width: _dragging ? 3 : 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _dragging ? Icons.file_download : Icons.slideshow,
                  size: 64,
                  color: _dragging ? Colors.blue : Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  _dragging
                      ? 'Thả file .eduvi vào đây'
                      : 'Kéo thả file .eduvi hoặc nhấn nút bên dưới',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: _openFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Mở file .eduvi'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## 10. Slide Viewer & Navigation

### `lib/screens/presentation_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/eduvi_schema.dart';
import '../services/asset_service.dart';
import '../widgets/slide_viewer.dart';

class PresentationScreen extends StatefulWidget {
  final EduViSchema schema;
  const PresentationScreen({super.key, required this.schema});

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  late PageController _pageController;
  late AssetService _assetService;
  int _currentPage = 0;
  int get _totalPages => widget.schema.cards.length;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _assetService = AssetService(widget.schema.assets);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (page < 0 || page >= _totalPages) return;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _next() => _goToPage(_currentPage + 1);
  void _prev() => _goToPage(_currentPage - 1);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.pageDown:
        _next();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.pageUp:
        _prev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        // Toggle fullscreen (cần window_manager)
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          children: [
            // Slide content
            PageView.builder(
              controller: _pageController,
              itemCount: _totalPages,
              onPageChanged: (page) => setState(() => _currentPage = page),
              itemBuilder: (context, index) {
                return SlideViewer(
                  card: widget.schema.cards[index],
                  assetService: _assetService,
                );
              },
            ),

            // Click zones: trái = prev, phải = next
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _prev,
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: const SizedBox.expand(), // vùng giữa không xử lý click
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _next,
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),

            // Progress bar dưới đáy
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: _buildProgressDots(),
            ),

            // Nút back
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // Page counter
            Positioned(
              top: 12,
              right: 16,
              child: Text(
                '${_currentPage + 1} / $_totalPages',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalPages, (i) {
        final isActive = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
```

---

## 11. Layout Renderer (Columns)

### `lib/widgets/slide_viewer.dart`

```dart
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/layout_model.dart';
import '../services/asset_service.dart';
import 'layout_renderer.dart';

class SlideViewer extends StatelessWidget {
  final EduViCard card;
  final AssetService assetService;

  const SlideViewer({
    super.key,
    required this.card,
    required this.assetService,
  });

  @override
  Widget build(BuildContext context) {
    // Xác định alignment
    final mainAxisAlignment = switch (card.contentAlignment) {
      'top' => MainAxisAlignment.start,
      'bottom' => MainAxisAlignment.end,
      _ => MainAxisAlignment.center,
    };

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: card.backgroundColor ?? const Color(0xFFFFFFFF),
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Column(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final layout in card.layouts)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: LayoutRenderer(
                layout: layout,
                assetService: assetService,
              ),
            ),
        ],
      ),
    );
  }
}
```

### `lib/widgets/layout_renderer.dart`

```dart
import 'package:flutter/material.dart';
import '../models/layout_model.dart';
import '../models/block_model.dart';
import '../services/asset_service.dart';
import 'blocks/block_dispatcher.dart';

class LayoutRenderer extends StatelessWidget {
  final EduViLayout layout;
  final AssetService assetService;

  const LayoutRenderer({
    super.key,
    required this.layout,
    required this.assetService,
  });

  @override
  Widget build(BuildContext context) {
    if (layout.columnCount <= 1) {
      // SINGLE: Stack tất cả blocks theo chiều dọc
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final block in layout.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BlockDispatcher(
                block: block,
                assetService: assetService,
              ),
            ),
        ],
      );
    }

    // MULTI-COLUMN: Chia blocks theo columnIndex
    final columns = List.generate(layout.columnCount, (col) {
      return layout.blocks.where((b) => b.columnIndex == col).toList();
    });

    final widths = layout.columnWidths ??
        List.filled(layout.columnCount, 100.0 / layout.columnCount);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int col = 0; col < layout.columnCount; col++) ...[
          if (col > 0) const SizedBox(width: 16), // gap
          Expanded(
            flex: (widths[col] * 100).round(), // dùng flex ratio
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final block in columns[col])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: BlockDispatcher(
                      block: block,
                      assetService: assetService,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
```

---

## 12. Block Renderers

### `lib/widgets/blocks/block_dispatcher.dart`

Dispatch block tới đúng widget theo `type`:

```dart
import 'package:flutter/material.dart';
import '../../models/block_model.dart';
import '../../services/asset_service.dart';
import 'text_block_widget.dart';
import 'heading_block_widget.dart';
import 'image_block_widget.dart';
import 'video_block_widget.dart';
import 'quiz_block_widget.dart';
import 'flashcard_block_widget.dart';
import 'fill_blank_block_widget.dart';

class BlockDispatcher extends StatelessWidget {
  final EduViBlock block;
  final AssetService assetService;

  const BlockDispatcher({
    super.key,
    required this.block,
    required this.assetService,
  });

  @override
  Widget build(BuildContext context) {
    return switch (block.type) {
      'TEXT' => TextBlockWidget(block: block),
      'HEADING' => HeadingBlockWidget(block: block),
      'IMAGE' => ImageBlockWidget(block: block, assetService: assetService),
      'VIDEO' => VideoBlockWidget(block: block, assetService: assetService),
      'QUIZ' => QuizBlockWidget(block: block),
      'FLASHCARD' => FlashcardBlockWidget(block: block),
      'FILL_BLANK' => FillBlankBlockWidget(block: block),
      _ => Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey.shade200,
          child: Text('Unsupported block type: ${block.type}'),
        ),
    };
  }
}
```

### `lib/widgets/blocks/text_block_widget.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../../models/block_model.dart';

class TextBlockWidget extends StatelessWidget {
  final EduViBlock block;
  const TextBlockWidget({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final html = block.html;
    if (html.isEmpty) return const SizedBox.shrink();

    return HtmlWidget(
      html,
      textStyle: const TextStyle(fontSize: 18, height: 1.6, color: Colors.white),
    );
  }
}
```

### `lib/widgets/blocks/heading_block_widget.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../../models/block_model.dart';

class HeadingBlockWidget extends StatelessWidget {
  final EduViBlock block;
  const HeadingBlockWidget({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final html = block.html;
    if (html.isEmpty) return const SizedBox.shrink();

    // Nếu html đã có tag <h1>-<h6>, render trực tiếp
    // Nếu không, wrap trong heading tag tương ứng
    final level = block.headingLevel;
    final wrappedHtml = html.startsWith('<h') ? html : '<h$level>$html</h$level>';

    return HtmlWidget(
      wrappedHtml,
      textStyle: const TextStyle(color: Colors.white),
    );
  }
}
```

### `lib/widgets/blocks/image_block_widget.dart`

```dart
import 'package:flutter/material.dart';
import '../../models/block_model.dart';
import '../../services/asset_service.dart';

class ImageBlockWidget extends StatelessWidget {
  final EduViBlock block;
  final AssetService assetService;

  const ImageBlockWidget({
    super.key,
    required this.block,
    required this.assetService,
  });

  @override
  Widget build(BuildContext context) {
    // Nếu src rỗng → show placeholder
    if (block.missingMedia || block.src.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported, color: Colors.white38, size: 48),
            if (block.alt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  block.alt,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Resolve embedded asset
    final bytes = assetService.resolve(block.src);
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(bytes, fit: BoxFit.contain),
      );
    }

    // Fallback: network image
    if (block.src.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(block.src, fit: BoxFit.contain),
      );
    }

    return const SizedBox.shrink();
  }
}
```

### `lib/widgets/blocks/video_block_widget.dart`

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import '../../models/block_model.dart';
import '../../services/asset_service.dart';

class VideoBlockWidget extends StatefulWidget {
  final EduViBlock block;
  final AssetService assetService;

  const VideoBlockWidget({
    super.key,
    required this.block,
    required this.assetService,
  });

  @override
  State<VideoBlockWidget> createState() => _VideoBlockWidgetState();
}

class _VideoBlockWidgetState extends State<VideoBlockWidget> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    final src = widget.block.src;

    if (src.startsWith('asset://')) {
      // Embedded base64 → ghi tạm ra file rồi play
      final bytes = widget.assetService.resolve(src);
      if (bytes == null) return;

      final mime = widget.assetService.getMimeType(src) ?? 'video/mp4';
      final ext = mime.contains('webm') ? 'webm' : 'mp4';
      final tmpDir = Directory.systemTemp;
      final assetId = src.replaceFirst('asset://', '');
      final tmpFile = File(p.join(tmpDir.path, 'eduvi_$assetId.$ext'));

      if (!await tmpFile.exists()) {
        await tmpFile.writeAsBytes(bytes);
      }
      await _player.open(Media(tmpFile.path));
    } else if (src.startsWith('http')) {
      await _player.open(Media(src));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.block.missingMedia || widget.block.src.isEmpty) {
      return Container(
        height: 300,
        color: Colors.grey.shade900,
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white38, size: 48),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Video(controller: _controller),
    );
  }
}
```

---

## 13. Interactive Blocks

### `lib/widgets/blocks/quiz_block_widget.dart`

```dart
import 'package:flutter/material.dart';
import '../../models/block_model.dart';

class QuizBlockWidget extends StatefulWidget {
  final EduViBlock block;
  const QuizBlockWidget({super.key, required this.block});

  @override
  State<QuizBlockWidget> createState() => _QuizBlockWidgetState();
}

class _QuizBlockWidgetState extends State<QuizBlockWidget> {
  int _currentQ = 0;
  int? _selectedOption;
  bool _showResult = false;
  int _score = 0;

  List<dynamic> get _questions =>
      widget.block.content['questions'] as List<dynamic>? ?? [];

  Map<String, dynamic> get _currentQuestion =>
      _questions[_currentQ] as Map<String, dynamic>;

  void _selectOption(int index) {
    if (_showResult) return;
    final correctIndex = _currentQuestion['correctIndex'] as int;
    setState(() {
      _selectedOption = index;
      _showResult = true;
      if (index == correctIndex) _score++;
    });
  }

  void _nextQuestion() {
    setState(() {
      _currentQ++;
      _selectedOption = null;
      _showResult = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return const Center(child: Text('Không có câu hỏi'));
    }

    // Quiz hoàn thành
    if (_currentQ >= _questions.length) {
      return _buildScoreCard();
    }

    final q = _currentQuestion;
    final options = q['options'] as List<dynamic>? ?? [];
    final correctIndex = q['correctIndex'] as int;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress
          Text(
            'Câu ${_currentQ + 1} / ${_questions.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 12),

          // Question
          Text(
            q['question'] as String? ?? '',
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),

          // Options
          for (int i = 0; i < options.length; i++) ...[
            _buildOption(i, options[i] as Map<String, dynamic>, correctIndex),
            const SizedBox(height: 8),
          ],

          // Explanation
          if (_showResult && q['explanation'] != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                q['explanation'] as String,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ],

          // Next button
          if (_showResult) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _nextQuestion,
                child: Text(_currentQ + 1 < _questions.length
                    ? 'Câu tiếp →'
                    : 'Xem kết quả'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOption(
      int index, Map<String, dynamic> option, int correctIndex) {
    Color bg = Colors.white.withOpacity(0.08);
    Color border = Colors.white24;

    if (_showResult) {
      if (index == correctIndex) {
        bg = Colors.green.withOpacity(0.2);
        border = Colors.green;
      } else if (index == _selectedOption) {
        bg = Colors.red.withOpacity(0.2);
        border = Colors.red;
      }
    } else if (index == _selectedOption) {
      border = Colors.blue;
    }

    return GestureDetector(
      onTap: () => _selectOption(index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Text(
          option['text'] as String? ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
          const SizedBox(height: 16),
          Text(
            '$_score / ${_questions.length}',
            style: const TextStyle(
                color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _score == _questions.length ? 'Xuất sắc!' : 'Cố gắng hơn nhé!',
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _currentQ = 0;
                _selectedOption = null;
                _showResult = false;
                _score = 0;
              });
            },
            child: const Text('Làm lại'),
          ),
        ],
      ),
    );
  }
}
```

### `lib/widgets/blocks/flashcard_block_widget.dart`

```dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../../models/block_model.dart';

class FlashcardBlockWidget extends StatefulWidget {
  final EduViBlock block;
  const FlashcardBlockWidget({super.key, required this.block});

  @override
  State<FlashcardBlockWidget> createState() => _FlashcardBlockWidgetState();
}

class _FlashcardBlockWidgetState extends State<FlashcardBlockWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _showFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  void _flip() {
    if (_showFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    _showFront = !_showFront;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final front = widget.block.content['front'] as String? ?? '';
    final back = widget.block.content['back'] as String? ?? '';

    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * pi;
          final isFrontVisible = angle < pi / 2;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective
              ..rotateY(angle),
            child: isFrontVisible
                ? _buildSide(front, 'Nhấn để lật', Colors.blue.shade800)
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: _buildSide(back, 'Nhấn để lật lại', Colors.teal.shade800),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildSide(String html, String hint, Color color) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 200),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HtmlWidget(html, textStyle: const TextStyle(color: Colors.white, fontSize: 20)),
          const SizedBox(height: 16),
          Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }
}
```

### `lib/widgets/blocks/fill_blank_block_widget.dart`

```dart
import 'package:flutter/material.dart';
import '../../models/block_model.dart';

class FillBlankBlockWidget extends StatefulWidget {
  final EduViBlock block;
  const FillBlankBlockWidget({super.key, required this.block});

  @override
  State<FillBlankBlockWidget> createState() => _FillBlankBlockWidgetState();
}

class _FillBlankBlockWidgetState extends State<FillBlankBlockWidget> {
  late List<TextEditingController> _controllers;
  late List<bool?> _results; // null = chưa check, true/false
  bool _checked = false;

  List<String> get _blanks =>
      (widget.block.content['blanks'] as List<dynamic>? ?? [])
          .map((b) => b.toString())
          .toList();

  String get _sentence =>
      widget.block.content['sentence'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_blanks.length, (_) => TextEditingController());
    _results = List.filled(_blanks.length, null);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _check() {
    setState(() {
      _checked = true;
      for (int i = 0; i < _blanks.length; i++) {
        _results[i] = _controllers[i].text.trim().toLowerCase() ==
            _blanks[i].trim().toLowerCase();
      }
    });
  }

  void _reset() {
    setState(() {
      _checked = false;
      for (final c in _controllers) {
        c.clear();
      }
      _results = List.filled(_blanks.length, null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Tách câu theo [blank]
    final parts = _sentence.split(RegExp(r'\[.*?\]'));
    int blankIdx = 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < parts.length; i++) ...[
                Text(
                  parts[i],
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                if (i < parts.length - 1 && blankIdx < _blanks.length)
                  _buildBlankField(blankIdx++),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              ElevatedButton(
                onPressed: _checked ? _reset : _check,
                child: Text(_checked ? 'Làm lại' : 'Kiểm tra'),
              ),
              if (_checked) ...[
                const SizedBox(width: 12),
                Text(
                  '${_results.where((r) => r == true).length} / ${_blanks.length} đúng',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBlankField(int index) {
    Color borderColor = Colors.white38;
    if (_checked && _results[index] != null) {
      borderColor = _results[index]! ? Colors.green : Colors.red;
    }

    return Container(
      width: 120,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: TextField(
        controller: _controllers[index],
        enabled: !_checked,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: borderColor, width: 2),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2),
          ),
          disabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: borderColor, width: 2),
          ),
        ),
      ),
    );
  }
}
```

---

## 14. Slide Transitions & Animations

Trong `PresentationScreen`, thay `PageView` bằng animated transitions:

```dart
// Trong PageView.builder, bọc mỗi slide trong AnimatedSwitcher:
PageView.builder(
  controller: _pageController,
  physics: const NeverScrollableScrollPhysics(), // disable swipe
  itemCount: _totalPages,
  itemBuilder: (context, index) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            )),
            child: child,
          ),
        );
      },
      child: SlideViewer(
        key: ValueKey(card.id),
        card: widget.schema.cards[index],
        assetService: _assetService,
      ),
    );
  },
);
```

---

## 15. Build & Release

### Debug chạy thử

```bash
flutter run -d windows
```

### Build production (Windows)

```bash
flutter build windows --release
```

Output tại: `build/windows/x64/runner/Release/`

Folder này chứa `.exe` + DLLs — zip lại là có thể distribute.

### Build MSIX installer (optional)

```yaml
# pubspec.yaml
dev_dependencies:
  msix: ^3.16.8
```

```bash
dart run msix:create
```

---

## 16. Cấu trúc thư mục hoàn chỉnh

```
eduvi_viewer/
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── eduvi_schema.dart
│   │   ├── card_model.dart
│   │   ├── layout_model.dart
│   │   └── block_model.dart
│   ├── services/
│   │   ├── file_service.dart
│   │   └── asset_service.dart
│   ├── screens/
│   │   ├── home_screen.dart
│   │   └── presentation_screen.dart
│   ├── widgets/
│   │   ├── slide_viewer.dart
│   │   ├── layout_renderer.dart
│   │   └── blocks/
│   │       ├── block_dispatcher.dart
│   │       ├── text_block_widget.dart
│   │       ├── heading_block_widget.dart
│   │       ├── image_block_widget.dart
│   │       ├── video_block_widget.dart
│   │       ├── quiz_block_widget.dart
│   │       ├── flashcard_block_widget.dart
│   │       └── fill_blank_block_widget.dart
│   └── theme/
│       └── app_theme.dart
├── pubspec.yaml
├── windows/
├── macos/
└── linux/
```

---

## Checklist triển khai

- [ ] Flutter SDK + Visual Studio C++ đã cài
- [ ] `flutter create` + cài dependencies
- [ ] Data models parse được file `.eduvi` mẫu
- [ ] Home screen: mở file + drag-drop
- [ ] Slide viewer: hiện text/heading blocks
- [ ] Layout renderer: SINGLE + TWO_COLUMN + THREE_COLUMN + SIDEBAR
- [ ] Image block: embedded base64 + placeholder khi `missingMedia`
- [ ] Video block: play embedded video qua `media_kit`
- [ ] Quiz block: chọn đáp án, hiện explanation, tính điểm
- [ ] Flashcard block: 3D flip animation
- [ ] Fill-blank block: nhập đáp án, kiểm tra
- [ ] Keyboard navigation: ←→, Space, Escape
- [ ] Slide transitions: fade + slide
- [ ] Build Windows release
