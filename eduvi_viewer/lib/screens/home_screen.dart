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
  bool _handledInitialFile = false;
  LastOpenedEduViInfo? _lastOpenedInfo;

  @override
  void initState() {
    super.initState();
    _loadLastOpened();
  }

  Future<void> _loadLastOpened() async {
    final saved = await RecentFileService.getLastOpened();
    if (!mounted) return;
    setState(() => _lastOpenedInfo = saved);
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

      final schema = await FileService.parseFile(resolvedPath);

      await RecentFileService.saveLastOpened(filePath: resolvedPath, schema: schema);
      final updated = await RecentFileService.getLastOpened();
      if (mounted) {
        setState(() => _lastOpenedInfo = updated);
      }

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
          SnackBar(content: Text('Loi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const _HomeBackground(),
          DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) {
              final files = details.files;
              if (
                  files.isNotEmpty &&
                  files.first.path.toLowerCase().endsWith('.eduvi')) {
                _openFile(files.first.path);
              }
            },
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1020),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withOpacity(0.28)),
                          ),
                          child: const Text(
                            'EduVi Desktop Viewer',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Mo bai giang offline\nnhanh va ro rang',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 42,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Keo-tha file .eduvi de bat dau. App se giu nguyen slide, media va bo cuc tu file export.',
                        style: theme.textTheme.titleMedium?.copyWith(color: Colors.white.withOpacity(0.86), height: 1.4),
                      ),
                      const SizedBox(height: 26),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(_dragging ? 0.20 : 0.12),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _dragging ? const Color(0xFF93C5FD) : Colors.white.withOpacity(0.26),
                            width: _dragging ? 2.2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 28,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _dragging ? Icons.file_download_done : Icons.slideshow_rounded,
                              size: 62,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _dragging ? 'Tha file .eduvi vao day' : 'Keo tha file vao day',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Hoac chon file bang File Explorer',
                              style: TextStyle(color: Colors.white.withOpacity(0.86)),
                            ),
                            const SizedBox(height: 18),
                            _loading
                                ? const CircularProgressIndicator(strokeWidth: 2.4)
                                : FilledButton.icon(
                                    onPressed: _openFile,
                                    icon: const Icon(Icons.folder_open),
                                    label: const Text('Mo file .eduvi'),
                                  ),
                          ],
                        ),
                      ),
                      if (_lastOpenedInfo != null) ...[
                        const SizedBox(height: 14),
                        _LastOpenedCard(info: _lastOpenedInfo!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBackground extends StatelessWidget {
  const _HomeBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B1220),
            Color(0xFF0C4A6E),
            Color(0xFF1D4ED8),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -60,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.09),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -90,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LastOpenedCard extends StatelessWidget {
  final LastOpenedEduViInfo info;

  const _LastOpenedCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final openedAt = DateTime.tryParse(info.openedAt)?.toLocal();
    final sourceUpdatedAt = DateTime.tryParse(info.updatedAt)?.toLocal();
    final openedLabel = openedAt == null
        ? info.openedAt
        : '${openedAt.day.toString().padLeft(2, '0')}/${openedAt.month.toString().padLeft(2, '0')}/${openedAt.year} ${openedAt.hour.toString().padLeft(2, '0')}:${openedAt.minute.toString().padLeft(2, '0')}';
    final updatedLabel = sourceUpdatedAt == null
      ? info.updatedAt
      : '${sourceUpdatedAt.day.toString().padLeft(2, '0')}/${sourceUpdatedAt.month.toString().padLeft(2, '0')}/${sourceUpdatedAt.year} ${sourceUpdatedAt.hour.toString().padLeft(2, '0')}:${sourceUpdatedAt.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Da mo gan nhat',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            info.title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
          ),
          if ((info.projectName ?? '').isNotEmpty || (info.subjectName ?? '').isNotEmpty || (info.gradeName ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  info.projectName,
                  info.subjectName,
                  info.gradeName,
                ].where((e) => (e ?? '').isNotEmpty).join(' • '),
                style: TextStyle(color: Colors.white.withOpacity(0.90)),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            openedLabel,
            style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 12),
          ),
          if (updatedLabel.isNotEmpty)
            Text(
              'Cap nhat noi dung: $updatedLabel',
              style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 12),
            ),
          const SizedBox(height: 2),
          Text(
            info.filePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withOpacity(0.70), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
