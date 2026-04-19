import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../services/file_service.dart';
import '../services/recent_file_service.dart';
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

      final schema = await FileService.parseFile(openedPath);

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
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
            Row(
              children: [
                _HomeSidebar(onOpenFile: _openFile, onRefresh: _loadHistory),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trang chủ',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: const Color(0xFF0F172A),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mở và quản lý các bài giảng gần đây theo phong cách desktop.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _QuickOpenPanel(
                          dragging: _dragging,
                          loading: _loading,
                          onOpenFile: _openFile,
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _RecentTablePanel(
                            entries: _historyEntries,
                            loading: _historyLoading,
                            onOpenEntry: (entry) => _openFile(entry.filePath),
                            formatDate: _formatDate,
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
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF2563EB),
                          width: 2,
                        ),
                        color: const Color(0x262563EB),
                      ),
                      child: const Center(
                        child: Text(
                          'Thả file .eduvi để mở ngay',
                          style: TextStyle(
                            color: Color(0xFF1D4ED8),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
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
  final VoidCallback onRefresh;

  const _HomeSidebar({required this.onOpenFile, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFD7E3F1))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.slideshow, color: Color(0xFF2563EB)),
          ),
          const SizedBox(height: 16),
          const _SidebarButton(
            icon: Icons.home_rounded,
            label: 'Trang chủ',
            selected: true,
          ),
          _SidebarButton(
            icon: Icons.folder_open_rounded,
            label: 'Mở file',
            onTap: onOpenFile,
          ),
          _SidebarButton(
            icon: Icons.refresh_rounded,
            label: 'Làm mới',
            onTap: onRefresh,
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'EduVi',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _SidebarButton({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = selected
        ? const Color(0xFF2563EB)
        : const Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: const Color(0xFFBFDBFE))
              : Border.all(color: Colors.transparent),
        ),
        child: Column(
          children: [
            Icon(icon, color: activeColor, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: activeColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
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
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dragging ? const Color(0xFF60A5FA) : const Color(0xFFD7E3F1),
          width: dragging ? 1.6 : 1,
        ),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dragging ? 'Thả file để mở ngay' : 'Mở bài giảng nhanh',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Kéo-thả file .eduvi vào cửa sổ hoặc chọn trực tiếp từ File Explorer.',
                  style: TextStyle(color: Color(0xFF475569), height: 1.4),
                ),
              ],
            ),
          ),
          if (loading)
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            FilledButton.icon(
              onPressed: onOpenFile,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Mở file .eduvi'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentTablePanel extends StatelessWidget {
  final List<EduViHistoryEntry> entries;
  final bool loading;
  final ValueChanged<EduViHistoryEntry> onOpenEntry;
  final String Function(String iso) formatDate;

  const _RecentTablePanel({
    required this.entries,
    required this.loading,
    required this.onOpenEntry,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: const Color(0xFF64748B),
      fontWeight: FontWeight.w600,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E3F1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                const Text(
                  'Lịch sử gần đây',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
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
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(flex: 5, child: Text('Tên file', style: labelStyle)),
                Expanded(
                  flex: 2,
                  child: Text('Lần mở gần nhất', style: labelStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Cập nhật nội dung', style: labelStyle),
                ),
                const SizedBox(
                  width: 100,
                  child: Text(
                    'Hành động',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : entries.isEmpty
                ? const Center(
                    child: Text(
                      'Chưa có lịch sử mở file .eduvi',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return InkWell(
                        onTap: () => onOpenEntry(entry),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: const Icon(
                                        Icons.slideshow_rounded,
                                        size: 16,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF0F172A),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            entry.filePath,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF64748B),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  formatDate(entry.openedAt),
                                  style: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  formatDate(entry.updatedAt),
                                  style: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 100,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => onOpenEntry(entry),
                                    icon: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Mở lại'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, _) =>
                        const Divider(color: Color(0xFFF1F5F9), height: 1),
                    itemCount: entries.length,
                  ),
          ),
        ],
      ),
    );
  }
}
