import 'dart:math';

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
import 'history_screen.dart';
import 'presentation_screen.dart';
import 'video_player_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? initialFilePath;

  const HomeScreen({super.key, this.initialFilePath});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
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

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _loadHistory();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
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
      if (imported.packageType == EduviPackageType.video) {
        final schema = await FileService.parseFile(imported.sourcePath ?? openedPath);
        await RecentFileService.saveLastOpened(
          filePath: openedPath,
          schema: schema,
        );
        await _loadHistory();

        if (mounted) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(schema: schema),
            ),
          );
        }
        return;
      }

      if (imported.packageType != EduviPackageType.slide) {
        throw const FormatException('Package hiện tại không phải slide/video');
      }

      final schema = await _slideRuntimeService.loadDeck(imported);
      final runtimeSessionId = '${imported.packageId}_${imported.version}';
      await _telemetry.info(
        'User opened slide package ${imported.packageId}@${imported.version}',
        category: 'home',
      );

      await RecentFileService.saveLastOpened(
        filePath: openedPath,
        schema: schema,
      );
      await _loadHistory();

      if (mounted) {
        final result = await Navigator.of(context).push<int>(
          MaterialPageRoute(
            builder: (_) => PresentationScreen(
              schema: schema,
              initialSlideIndex: _lastViewedSlidesByPath[openedPath] ?? 0,
              runtimeSessionId: runtimeSessionId,
              onExitSlideChanged: (slideIndex) {
                _lastViewedSlidesByPath[openedPath] = slideIndex;
              },
            ),
          ),
        );

        if (result != null) {
          _lastViewedSlidesByPath[openedPath] = result;
        }
      }
    } catch (e) {
      await _telemetry.error('Home open failed for path=$path error=$e', category: 'home');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Loi: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatRelativeDate(String iso) {
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;

    final now = DateTime.now();
    final diff = now.difference(parsed);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';

    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year}';
  }

  String _extractDisplayNameFromPath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final nonEmpty = normalized.split('/').where((part) => part.isNotEmpty).toList();
    final fileName = nonEmpty.isEmpty ? normalized : nonEmpty.last;
    const eduviSuffix = '.eduvi';
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

  int get _slideCount => _historyEntries.where((e) => !e.isGame && !e.isVideo).length;
  int get _gameCount => _historyEntries.where((e) => e.isGame).length;
  int get _videoCount => _historyEntries.where((e) => e.isVideo).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
            // Background with mesh gradient
            const _MeshBackground(),
            Row(
              children: [
                _HomeSidebar(
                  onOpenFile: _openFile,
                  onOpenHistory: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    ).then((_) => _loadHistory());
                  },
                ),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                      'EduVi Viewer',
                                      style: TextStyle(
                                        color: Color(0xFF1E40AF),
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                        height: 1.1,
                                      ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Mở và quản lý bài giảng offline của bạn',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              // Stats chips
                              if (!_historyLoading && _historyEntries.isNotEmpty)
                                Row(
                                  children: [
                                    _StatChip(
                                      icon: Icons.slideshow_rounded,
                                      label: '$_slideCount Slides',
                                      color: const Color(0xFF3B82F6),
                                    ),
                                    const SizedBox(width: 8),
                                    _StatChip(
                                      icon: Icons.sports_esports_rounded,
                                      label: '$_gameCount Games',
                                      color: const Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 8),
                                    _StatChip(
                                      icon: Icons.ondemand_video_rounded,
                                      label: '$_videoCount Videos',
                                      color: const Color(0xFFEF4444),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Quick open hero
                          _HeroDropZone(
                            dragging: _dragging,
                            loading: _loading,
                            onOpenFile: _openFile,
                          ),
                          const SizedBox(height: 20),
                          // Recent files
                          Expanded(
                            child: _RecentFilesGrid(
                              entries: _historyEntries,
                              loading: _historyLoading,
                              onOpenEntry: (entry) => _openFile(entry.filePath),
                              formatDate: _formatRelativeDate,
                              formatEntryTitle: _displayHistoryTitle,
                              onViewAll: () {
                                Navigator.of(context).push<void>(
                                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                                ).then((_) => _loadHistory());
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Drag overlay
            if (_dragging) const _DragOverlay(),
          ],
        ),
      ),
    );
  }
}

// ─── Background ───────────────────────────────────────────────────────────────

class _MeshBackground extends StatelessWidget {
  const _MeshBackground();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF1F5F9)],
          ),
        ),
      ),
    );
  }
}

// ─── Sidebar ──────────────────────────────────────────────────────────────────

class _HomeSidebar extends StatelessWidget {
  final VoidCallback onOpenFile;
  final VoidCallback onOpenHistory;

  const _HomeSidebar({required this.onOpenFile, required this.onOpenHistory});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          right: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Logo
          Container(
            key: const Key('home-sidebar-logo'),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0xFF2563EB),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x302563EB),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              'assets/eduvi_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(height: 28),
          // Nav items
          _SidebarIcon(
            icon: Icons.home_rounded,
            tooltip: 'Trang chủ',
            active: true,
            onTap: () {},
          ),
          const SizedBox(height: 4),
          _SidebarIcon(
            icon: Icons.folder_open_rounded,
            tooltip: 'Mở file',
            onTap: onOpenFile,
          ),
          const SizedBox(height: 4),
          _SidebarIcon(
            icon: Icons.history_rounded,
            tooltip: 'Lịch sử',
            onTap: onOpenHistory,
          ),
          const Spacer(),
          Container(
            width: 32,
            height: 1,
            color: const Color(0xFFE2E8F0),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'v4',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onTap;

  const _SidebarIcon({
    required this.icon,
    required this.tooltip,
    this.active = false,
    this.onTap,
  });

  @override
  State<_SidebarIcon> createState() => _SidebarIconState();
}

class _SidebarIconState extends State<_SidebarIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.active;
    final isHot = _hovered || isActive;

    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFFEFF6FF)
                  : (_hovered ? const Color(0xFFF1F5F9) : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 20,
              color: isHot ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Stat Chip ────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hero Drop Zone ───────────────────────────────────────────────────────────

class _HeroDropZone extends StatefulWidget {
  final bool dragging;
  final bool loading;
  final VoidCallback onOpenFile;

  const _HeroDropZone({
    required this.dragging,
    required this.loading,
    required this.onOpenFile,
  });

  @override
  State<_HeroDropZone> createState() => _HeroDropZoneState();
}

class _HeroDropZoneState extends State<_HeroDropZone> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDragging = widget.dragging;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDragging
                ? [const Color(0xFFEFF6FF), const Color(0xFFE0F2FE)]
                : [
                    Colors.white,
                    const Color(0xFFF8FAFC),
                  ],
          ),
          border: Border.all(
            color: isDragging
                ? const Color(0xFF3B82F6)
                : (_hovered ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0)),
            width: isDragging ? 2 : 1,
          ),
          boxShadow: [
            if (isDragging)
              const BoxShadow(
                color: Color(0x303B82F6),
                blurRadius: 32,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Row(
          children: [
            // Icon area
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDragging
                      ? [const Color(0xFF2563EB), const Color(0xFF7C3AED)]
                      : [const Color(0xFFEFF6FF), const Color(0xFFE0F2FE)],
                ),
              ),
              child: Icon(
                isDragging ? Icons.downloading_rounded : Icons.add_rounded,
                size: 28,
                color: isDragging ? Colors.white : const Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(width: 20),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isDragging ? 'Thả file vào đây...' : 'Mở bài giảng',
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDragging
                        ? 'Nhả chuột để mở file .eduvi ngay lập tức'
                        : 'Kéo-thả file .eduvi vào đây hoặc nhấn nút để chọn từ máy tính',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Button
            if (widget.loading)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                ),
              )
            else
              _GlowButton(
                label: 'Mở file .eduvi',
                icon: Icons.folder_open_rounded,
                onPressed: widget.onOpenFile,
              ),
          ],
        ),
      ),
    );
  }
}

class _GlowButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _GlowButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _hovered ? const Color(0xFF1D4ED8) : const Color(0xFF2563EB),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: _hovered ? 0.35 : 0.2),
                blurRadius: _hovered ? 16 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Recent Files Grid ────────────────────────────────────────────────────────

class _RecentFilesGrid extends StatelessWidget {
  final List<EduViHistoryEntry> entries;
  final bool loading;
  final ValueChanged<EduViHistoryEntry> onOpenEntry;
  final String Function(String iso) formatDate;
  final String Function(EduViHistoryEntry entry) formatEntryTitle;
  final VoidCallback onViewAll;

  const _RecentFilesGrid({
    required this.entries,
    required this.loading,
    required this.onOpenEntry,
    required this.formatDate,
    required this.formatEntryTitle,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Section header
        Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 18, color: Color(0xFF6B7280)),
            const SizedBox(width: 8),
            const Text(
              'Gần đây',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            if (!loading && entries.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${entries.length}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Spacer(),
            if (entries.isNotEmpty)
              _TextButton(
                label: 'Xem tất cả',
                onTap: onViewAll,
              ),
          ],
        ),
        const SizedBox(height: 14),
        // Content
        Expanded(
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3B82F6),
                  ),
                )
              : entries.isEmpty
                  ? const _EmptyState()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = max(1, (constraints.maxWidth / 320).floor());
                        return GridView.builder(
                          padding: const EdgeInsets.only(bottom: 8),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 2.6,
                          ),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return _FileCard(
                              entry: entry,
                              displayTitle: formatEntryTitle(entry),
                              timeAgo: formatDate(entry.openedAt),
                              onOpen: () => onOpenEntry(entry),
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _TextButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _TextButton({required this.label, required this.onTap});

  @override
  State<_TextButton> createState() => _TextButtonState();
}

class _TextButtonState extends State<_TextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                color: _hovered ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: _hovered ? const Color(0xFF2563EB) : const Color(0xFF64748B),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── File Card ────────────────────────────────────────────────────────────────

class _FileCard extends StatefulWidget {
  final EduViHistoryEntry entry;
  final String displayTitle;
  final String timeAgo;
  final VoidCallback onOpen;

  const _FileCard({
    required this.entry,
    required this.displayTitle,
    required this.timeAgo,
    required this.onOpen,
  });

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isGame = widget.entry.isGame;
    final isVideo = widget.entry.isVideo;

    final Color accentColor;
    final IconData iconData;
    final String typeLabel;

    if (isGame) {
      accentColor = const Color(0xFFF59E0B);
      iconData = Icons.sports_esports_rounded;
      typeLabel = 'Game';
    } else if (isVideo) {
      accentColor = const Color(0xFFEF4444);
      iconData = Icons.ondemand_video_rounded;
      typeLabel = 'Video';
    } else {
      accentColor = const Color(0xFF3B82F6);
      iconData = Icons.slideshow_rounded;
      typeLabel = 'Slide';
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hovered ? const Color(0xFFF8FAFC) : Colors.white,
            border: Border.all(
              color: _hovered
                  ? accentColor.withValues(alpha: 0.3)
                  : const Color(0xFFE5E7EB),
            ),
            boxShadow: [
              if (_hovered)
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              // Type icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: accentColor.withValues(alpha: _hovered ? 0.15 : 0.1),
                ),
                child: Icon(iconData, size: 22, color: accentColor),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _hovered ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.entry.filePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.timeAgo,
                      style: TextStyle(
                        color: accentColor.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Open arrow
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _hovered ? 1.0 : 0.0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: accentColor.withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: accentColor,
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

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0xFFF1F5F9),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(
              Icons.folder_open_rounded,
              size: 36,
              color: Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Chưa có bài giảng nào',
            style: TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kéo-thả hoặc nhấn Mở file để bắt đầu sử dụng',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Drag Overlay ─────────────────────────────────────────────────────────────

class _DragOverlay extends StatelessWidget {
  const _DragOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCCFFFFFF),
          ),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E40AF), Color(0xFF7C3AED)],
                ),
                border: Border.all(
                  color: const Color(0xFF3B82F6),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x403B82F6),
                    blurRadius: 48,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                      ),
                    ),
                    child: const Icon(
                      Icons.cloud_upload_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Thả file .eduvi để mở ngay',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ho tro bai giang slide, video va game tuong tac',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
