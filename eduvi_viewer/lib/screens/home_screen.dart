import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../features/offline_core/domain/eduvi_package_type.dart';
import '../features/offline_core/services/eduvi_import_service.dart';
import '../features/offline_core/services/eduvi_package_classifier.dart';
import '../features/offline_core/services/game_session_manager.dart';
import '../features/offline_core/services/slide_runtime_service.dart';
import '../features/offline_core/services/telemetry_local_service.dart';
import '../services/file_service.dart';
import '../services/recent_file_service.dart';
import 'game_result_screen.dart';
import 'presentation_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? initialFilePath;

  const HomeScreen({super.key, this.initialFilePath});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _dragging = false;
  bool _loading = false;
  bool _historyLoading = true;
  bool _handledInitialFile = false;
  List<EduViHistoryEntry> _historyEntries = const [];
  final Map<String, int> _lastViewedSlidesByPath = {};
  final EduviPackageClassifier _packageClassifier = EduviPackageClassifier();
  final EduviImportService _importService = EduviImportService();
  final GameSessionManager _gameSessionManager = GameSessionManager();
  final SlideRuntimeService _slideRuntimeService = SlideRuntimeService();
  final TelemetryLocalService _telemetry = const TelemetryLocalService();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() => _historyLoading = true);
    }

    final history = await RecentFileService.getHistory(limit: 10);
    if (!mounted) return;
    setState(() {
      _historyEntries = history;
      _historyLoading = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_handledInitialFile) return;
    _handledInitialFile = true;

    final initial = widget.initialFilePath;
    if (initial == null || !initial.toLowerCase().endsWith('.eduvi')) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openFile(initial);
      }
    });
  }

  Future<void> _openFile([String? path]) async {
    setState(() => _loading = true);
    try {
      String? resolvedPath = path;
      resolvedPath ??= await FileService.pickEduViPath();
      if (resolvedPath == null || resolvedPath.isEmpty) {
        return;
      }
      final openedPath = resolvedPath;

      final packageType = await _packageClassifier.classifyFile(openedPath);
      if (packageType == EduviPackageType.game) {
        final displayTitle = _extractDisplayNameFromPath(openedPath);
        final launch = await _gameSessionManager.launchFromEduviFile(openedPath);
        await RecentFileService.saveGameOpened(
          filePath: openedPath,
          title: displayTitle,
        );
        await _loadHistory();
        await _telemetry.info(
          'User launched game package from $openedPath session=${launch.sessionId}',
          category: 'home',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Game đang chạy — kết quả sẽ hiển thị khi kết thúc.'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        // Await game process exit, then show results screen.
        launch.processExitCode.then((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          final resultData = await _gameSessionManager.readSessionResult(
            launch.outputDir,
          );
          if (!mounted) return;
          if (resultData != null) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GameResultScreen(
                  result: resultData,
                  packageTitle: displayTitle,
                  onPlayAgain: () => _openFile(openedPath),
                ),
              ),
            );
            if (mounted) await _loadHistory();
          }
        });
        return;
      }

      final imported = await _importService.importFromFile(openedPath);
      if (imported.packageType != EduviPackageType.slide) {
        throw const FormatException('Package hiện tại không phải slide');
      }

      final schema = await _slideRuntimeService.loadDeck(imported);
      final historyPath = imported.sourcePath ?? openedPath;
      final runtimeSessionId = '${imported.packageId}_${imported.version}';
      await _telemetry.info(
        'User opened slide package ${imported.packageId}@${imported.version}',
        category: 'home',
      );

      await RecentFileService.saveLastOpened(
        filePath: historyPath,
        schema: schema,
      );
      await _loadHistory();

      if (mounted) {
        final result = await Navigator.of(context).push<int>(
          MaterialPageRoute(
            builder: (_) => PresentationScreen(
              schema: schema,
              initialSlideIndex: _lastViewedSlidesByPath[historyPath] ?? 0,
              runtimeSessionId: runtimeSessionId,
              onExitSlideChanged: (slideIndex) {
                _lastViewedSlidesByPath[historyPath] = slideIndex;
              },
            ),
          ),
        );

        if (result != null) {
          _lastViewedSlidesByPath[historyPath] = result;
        }
      }
    } catch (e) {
      await _telemetry.error('Home open failed for path=$path error=$e', category: 'home');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String iso) {
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;

    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year} $hour:$minute';
  }

  String _extractDisplayNameFromPath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final nonEmpty = normalized.split('/').where((part) => part.isNotEmpty).toList();
    final fileName = nonEmpty.isEmpty ? normalized : nonEmpty.last;
    final eduviSuffix = '.eduvi';
    if (fileName.toLowerCase().endsWith(eduviSuffix)) {
      return fileName.substring(0, fileName.length - eduviSuffix.length);
    }
    return fileName;
  }

  String _displayHistoryTitle(EduViHistoryEntry entry) {
    final rawTitle = entry.title.trim();
    if (!entry.isGame) {
      return rawTitle.isEmpty ? _extractDisplayNameFromPath(entry.filePath) : rawTitle;
    }

    final legacyTechnicalTitle = RegExp(r'^game\s+[a-z0-9_]+$', caseSensitive: false);
    if (rawTitle.isEmpty || legacyTechnicalTitle.hasMatch(rawTitle)) {
      return _extractDisplayNameFromPath(entry.filePath);
    }

    return rawTitle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F6FF),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          final files = details.files;
          if (files.isNotEmpty &&
              files.first.path.toLowerCase().endsWith('.eduvi')) {
            _openFile(files.first.path);
          }
        },
        child: Stack(
          children: [
            // Gradient background
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF8FBFF), Color(0xFFECF2FF)],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _HomeSidebar(onOpenFile: _openFile),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trang chủ',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Quản lý và mở bài giảng EduVi nhanh chóng',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _QuickOpenPanel(
                          dragging: _dragging,
                          loading: _loading,
                          onOpenFile: _openFile,
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _RecentTablePanel(
                            entries: _historyEntries,
                            loading: _historyLoading,
                            onOpenEntry: (entry) => _openFile(entry.filePath),
                            formatDate: _formatDate,
                            formatEntryTitle: _displayHistoryTitle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: const Color(0x1A2563EB),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 36,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF2563EB),
                            width: 2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x302563EB),
                              blurRadius: 48,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_upload_outlined,
                              size: 72,
                              color: Color(0xFF2563EB),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Thả file .eduvi để mở ngay',
                              style: TextStyle(
                                color: Color(0xFF1D4ED8),
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Hỗ trợ bài giảng slide và game tương tác',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeSidebar extends StatelessWidget {
  final VoidCallback onOpenFile;

  const _HomeSidebar({required this.onOpenFile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      decoration: const BoxDecoration(
        color: Color(0xFAFFFFFF),
        border: Border(right: BorderSide(color: Color(0xFFDDE8F5))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A2563EB),
            blurRadius: 24,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            key: const Key('home-sidebar-logo'),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDDE8F8)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x142563EB),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Image.asset(
              'assets/eduvi_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.slideshow, color: Color(0xFF2563EB), size: 36),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'EduVi Viewer',
            style: TextStyle(
              color: Color(0xFF1E3A5F),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(
            color: Color(0xFFE8EFF8),
            height: 1,
            indent: 16,
            endIndent: 16,
          ),
          const SizedBox(height: 16),
          _SidebarButton(
            icon: Icons.folder_open_rounded,
            label: 'Mở file',
            onTap: onOpenFile,
          ),
          const Spacer(),
          const Divider(
            color: Color(0xFFE8EFF8),
            height: 1,
            indent: 16,
            endIndent: 16,
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16, top: 10),
            child: Column(
              children: [
                Text(
                  'EduVi Desktop',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'v4.0 · Offline',
                  style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SidebarButton({required this.icon, required this.label, this.onTap});

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFEFF6FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? const Color(0xFFBFDBFE) : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(
                widget.icon,
                color: _hovered ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                size: 24,
              ),
              const SizedBox(height: 5),
              Text(
                widget.label,
                style: TextStyle(
                  color: _hovered ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                  fontWeight: _hovered ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickOpenPanel extends StatelessWidget {
  final bool dragging;
  final bool loading;
  final VoidCallback onOpenFile;

  const _QuickOpenPanel({
    required this.dragging,
    required this.loading,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: dragging
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Color(0xFFF8FBFF)],
              ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dragging ? const Color(0xFF3B82F6) : const Color(0xFFD7E3F1),
          width: dragging ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: dragging ? const Color(0x202563EB) : const Color(0x06000000),
            blurRadius: dragging ? 28 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: dragging
                    ? const Color(0xFFDBEAFE)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                dragging
                    ? Icons.cloud_upload_rounded
                    : Icons.upload_file_rounded,
                size: 32,
                color: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dragging ? 'Thả file vào đây để mở' : 'Mở bài giảng',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Kéo-thả file .eduvi vào cửa sổ, hoặc nhấn "Mở file" để chọn từ máy tính.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            if (loading)
              const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              FilledButton.icon(
                onPressed: onOpenFile,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Mở file .eduvi'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  elevation: 2,
                  shadowColor: const Color(0x402563EB),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentTablePanel extends StatelessWidget {
  final List<EduViHistoryEntry> entries;
  final bool loading;
  final ValueChanged<EduViHistoryEntry> onOpenEntry;
  final String Function(String iso) formatDate;
  final String Function(EduViHistoryEntry entry) formatEntryTitle;

  const _RecentTablePanel({
    required this.entries,
    required this.loading,
    required this.onOpenEntry,
    required this.formatDate,
    required this.formatEntryTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E3F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Lịch sử gần đây',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    '${entries.length} mục',
                    style: const TextStyle(
                      color: Color(0xFF1D4ED8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EFF8)),
          // Column labels
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Row(
              children: [
                const Expanded(
                  flex: 5,
                  child: _ColLabel('Tên tài liệu'),
                ),
                const Expanded(
                  flex: 2,
                  child: _ColLabel('Lần mở gần nhất'),
                ),
                const Expanded(
                  flex: 2,
                  child: _ColLabel('Cập nhật nội dung'),
                ),
                const SizedBox(width: 90, child: _ColLabel('')),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EFF8)),
          // List
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : entries.isEmpty
                ? const _EmptyHistoryState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: Color(0xFFF1F5F9),
                      indent: 20,
                      endIndent: 20,
                    ),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _HistoryRow(
                        entry: entry,
                        displayTitle: formatEntryTitle(entry),
                        formattedOpened: formatDate(entry.openedAt),
                        formattedUpdated: formatDate(entry.updatedAt),
                        onOpen: () => onOpenEntry(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ColLabel extends StatelessWidget {
  final String text;
  const _ColLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.history_edu_rounded,
              size: 36,
              color: Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Chưa có lịch sử',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Mở file .eduvi để bắt đầu sử dụng EduVi Viewer',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatefulWidget {
  final EduViHistoryEntry entry;
  final String displayTitle;
  final String formattedOpened;
  final String formattedUpdated;
  final VoidCallback onOpen;

  const _HistoryRow({
    required this.entry,
    required this.displayTitle,
    required this.formattedOpened,
    required this.formattedUpdated,
    required this.onOpen,
  });

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isGame = widget.entry.isGame;
    final iconColor =
        isGame ? const Color(0xFFD97706) : const Color(0xFF2563EB);
    final iconBgColor =
        isGame ? const Color(0xFFFFF7ED) : const Color(0xFFEFF6FF);
    final iconData =
        isGame ? Icons.sports_esports_rounded : Icons.slideshow_rounded;
    final typeBgColor =
        isGame ? const Color(0xFFFEF3C7) : const Color(0xFFDBEAFE);
    final typeTextColor =
        isGame ? const Color(0xFFB45309) : const Color(0xFF1D4ED8);
    final typeLabel = isGame ? 'Game' : 'Slide';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _hovered ? const Color(0xFFF5F9FF) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              // Icon + title + path
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(iconData, size: 22, color: iconColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: typeBgColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  typeLabel,
                                  style: TextStyle(
                                    color: typeTextColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.entry.filePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Opened at
              Expanded(
                flex: 2,
                child: Text(
                  widget.formattedOpened,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                  ),
                ),
              ),
              // Updated at
              Expanded(
                flex: 2,
                child: Text(
                  widget.formattedUpdated,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                  ),
                ),
              ),
              // Action button (visible on hover)
              SizedBox(
                width: 90,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _hovered ? 1.0 : 0.0,
                    child: FilledButton.tonal(
                      onPressed: widget.onOpen,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDBEAFE),
                        foregroundColor: const Color(0xFF1D4ED8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Mở',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
