import 'dart:io';

import 'package:flutter/material.dart';

import '../features/offline_core/domain/eduvi_package_type.dart';
import '../features/offline_core/services/eduvi_package_classifier.dart';
import '../features/offline_core/services/game_session_manager.dart';

import '../services/file_service.dart';
import '../services/recent_file_service.dart';
import 'presentation_screen.dart';
import 'video_player_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _onlyVideo = false;
  bool _onlyQuiz = false;
  String? _selectedGrade;
  String? _selectedSubject;
  String? _selectedProject;
  String? _openingId;
  final Map<String, int> _lastViewedSlidesByPath = {};
  final EduviPackageClassifier _packageClassifier = EduviPackageClassifier();
  final GameSessionManager _gameSessionManager = GameSessionManager();

  List<EduViHistoryEntry> _allEntries = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final history = await RecentFileService.getHistory();
    history.sort((a, b) => b.openedAt.compareTo(a.openedAt));

    if (!mounted) return;
    setState(() {
      _allEntries = history;
      _loading = false;
    });
  }

  Future<void> _openFromHistory(EduViHistoryEntry entry) async {
    final file = File(entry.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy file trên máy.')),
      );
      return;
    }

    setState(() => _openingId = entry.id);
    try {
      final packageType = entry.isGame
          ? EduviPackageType.game
          : entry.isVideo
          ? EduviPackageType.video
          : await _packageClassifier.classifyFile(entry.filePath);

      if (packageType == EduviPackageType.game) {
        final launch = await _gameSessionManager.launchFromEduviFile(entry.filePath);
        await RecentFileService.saveGameOpened(
          filePath: entry.filePath,
          title: entry.title,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã mở game offline. Session: ${launch.sessionId} (PID: ${launch.processId})',
            ),
          ),
        );
        return;
      }

      final schema = await FileService.parseFile(entry.filePath);
      await RecentFileService.saveLastOpened(
        filePath: entry.filePath,
        schema: schema,
      );

      if (!mounted) return;
      if (packageType == EduviPackageType.video || schema.isVideoPackage) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(schema: schema),
          ),
        );
      } else {
        final result = await Navigator.of(context).push<int>(
          MaterialPageRoute(
            builder: (_) => PresentationScreen(
              schema: schema,
              initialSlideIndex: _lastViewedSlidesByPath[entry.filePath] ?? 0,
              onExitSlideChanged: (slideIndex) {
                _lastViewedSlidesByPath[entry.filePath] = slideIndex;
              },
            ),
          ),
        );

        if (result != null) {
          _lastViewedSlidesByPath[entry.filePath] = result;
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không mở được file: $e')));
    } finally {
      if (mounted) {
        setState(() => _openingId = null);
        await _loadHistory();
      }
    }
  }

  Future<void> _removeEntry(EduViHistoryEntry entry) async {
    await RecentFileService.removeHistoryEntry(entry.id);
    if (!mounted) return;
    await _loadHistory();
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Xóa lịch sử'),
          content: const Text('Bạn có chắc muốn xóa toàn bộ lịch sử mở file?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await RecentFileService.clearHistory();
    if (!mounted) return;
    await _loadHistory();
  }

  String _labelOf(String? code, String? name, String fallback) {
    final safeName = (name ?? '').trim();
    if (safeName.isNotEmpty) return safeName;

    final safeCode = (code ?? '').trim();
    if (safeCode.isNotEmpty) return safeCode;

    return fallback;
  }

  String _normalizedCode(String? code) {
    return (code ?? '').trim();
  }

  List<EduViHistoryEntry> get _filteredEntries {
    final query = _searchController.text.trim().toLowerCase();

    return _allEntries.where((entry) {
      if (_selectedGrade != null && _normalizedCode(entry.gradeCode) != _selectedGrade) {
        return false;
      }
      if (_selectedSubject != null && _normalizedCode(entry.subjectCode) != _selectedSubject) {
        return false;
      }
      if (_selectedProject != null && _normalizedCode(entry.projectCode) != _selectedProject) {
        return false;
      }
      if (_onlyVideo && !entry.hasVideo) return false;
      if (_onlyQuiz && !entry.hasQuiz) return false;

      if (query.isEmpty) return true;

      final haystack = [
        entry.title,
        entry.description,
        entry.filePath,
        entry.projectName,
        entry.subjectName,
        entry.gradeName,
        entry.projectCode,
        entry.subjectCode,
        entry.gradeCode,
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  List<_MetaOption> get _gradeOptions {
    final seen = <String>{};
    final options = <_MetaOption>[];

    for (final entry in _allEntries) {
      final code = _normalizedCode(entry.gradeCode);
      if (seen.contains(code)) continue;
      seen.add(code);
      options.add(
        _MetaOption(
          code: code,
          name: _labelOf(entry.gradeCode, entry.gradeName, 'Khối chưa rõ'),
        ),
      );
    }

    options.sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  List<_MetaOption> get _subjectOptions {
    final seen = <String>{};
    final options = <_MetaOption>[];

    for (final entry in _allEntries) {
      if (_selectedGrade != null && _normalizedCode(entry.gradeCode) != _selectedGrade) {
        continue;
      }
      final code = _normalizedCode(entry.subjectCode);
      if (seen.contains(code)) continue;
      seen.add(code);
      options.add(
        _MetaOption(
          code: code,
          name: _labelOf(entry.subjectCode, entry.subjectName, 'Môn chưa rõ'),
        ),
      );
    }

    options.sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  List<_MetaOption> get _projectOptions {
    final seen = <String>{};
    final options = <_MetaOption>[];

    for (final entry in _allEntries) {
      if (_selectedGrade != null && _normalizedCode(entry.gradeCode) != _selectedGrade) {
        continue;
      }
      if (_selectedSubject != null && _normalizedCode(entry.subjectCode) != _selectedSubject) {
        continue;
      }
      final code = _normalizedCode(entry.projectCode);
      if (seen.contains(code)) continue;
      seen.add(code);
      options.add(
        _MetaOption(
          code: code,
          name: _labelOf(entry.projectCode, entry.projectName, 'Dự án chưa rõ'),
        ),
      );
    }

    options.sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  Map<_MetaOption, Map<_MetaOption, Map<_MetaOption, List<EduViHistoryEntry>>>>
  _buildGroupedData(List<EduViHistoryEntry> source) {
    final grouped =
        <
          _MetaOption,
          Map<_MetaOption, Map<_MetaOption, List<EduViHistoryEntry>>>
        >{};

    for (final entry in source) {
      final grade = _MetaOption(
        code: _normalizedCode(entry.gradeCode),
        name: _labelOf(entry.gradeCode, entry.gradeName, 'Khối chưa rõ'),
      );
      final subject = _MetaOption(
        code: _normalizedCode(entry.subjectCode),
        name: _labelOf(entry.subjectCode, entry.subjectName, 'Môn chưa rõ'),
      );
      final project = _MetaOption(
        code: _normalizedCode(entry.projectCode),
        name: _labelOf(entry.projectCode, entry.projectName, 'Dự án chưa rõ'),
      );

      grouped.putIfAbsent(grade, () => {});
      grouped[grade]!.putIfAbsent(subject, () => {});
      grouped[grade]![subject]!.putIfAbsent(
        project,
        () => <EduViHistoryEntry>[],
      );
      grouped[grade]![subject]![project]!.add(entry);
    }

    return grouped;
  }

  String _formatTime(String iso) {
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
    final colorScheme = theme.colorScheme;
    final filtered = _filteredEntries;
    final grouped = _buildGroupedData(filtered);
    final gradeKeys = grouped.keys.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử mở file'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Xóa lịch sử',
            onPressed: _allEntries.isEmpty ? null : _clearHistory,
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: _buildFiltersCard(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Tổng ${filtered.length} / ${_allEntries.length} mục',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? const Center(child: Text('Chưa có lịch sử phù hợp bộ lọc.'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: gradeKeys.length,
                      itemBuilder: (context, index) {
                        final grade = gradeKeys[index];
                        final subjects = grouped[grade]!;
                        final subjectKeys = subjects.keys.toList()
                          ..sort((a, b) => a.name.compareTo(b.name));

                        final itemCount = subjects.values
                            .expand((projectMap) => projectMap.values)
                            .fold<int>(0, (sum, list) => sum + list.length);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            title: Text('${grade.name} ($itemCount)'),
                            subtitle: Text(grade.code ?? ''),
                            children: [
                              for (final subject in subjectKeys)
                                _buildSubjectTile(subject, subjects[subject]!),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectTile(
    _MetaOption subject,
    Map<_MetaOption, List<EduViHistoryEntry>> projects,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final projectKeys = projects.keys.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final itemCount = projects.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.68),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text('${subject.name} ($itemCount)'),
        subtitle: Text(subject.code ?? ''),
        children: [
          for (final project in projectKeys)
            _buildProjectSection(project, projects[project]!),
        ],
      ),
    );
  }

  Widget _buildProjectSection(
    _MetaOption project,
    List<EduViHistoryEntry> entries,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${project.name} (${entries.length})',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final entry in entries)
            _HistoryEntryCard(
              entry: entry,
              opening: _openingId == entry.id,
              formatTime: _formatTime,
              onOpen: () => _openFromHistory(entry),
              onRemove: () => _removeEntry(entry),
            ),
        ],
      ),
    );
  }

  Widget _buildFiltersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Tìm theo tên bài, đường dẫn, metadata...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildDropdown(
                  label: 'Khối',
                  value: _selectedGrade,
                  options: _gradeOptions,
                  onChanged: (value) {
                    setState(() {
                      _selectedGrade = value;
                      _selectedSubject = null;
                      _selectedProject = null;
                    });
                  },
                ),
                _buildDropdown(
                  label: 'Môn',
                  value: _selectedSubject,
                  options: _subjectOptions,
                  onChanged: (value) {
                    setState(() {
                      _selectedSubject = value;
                      _selectedProject = null;
                    });
                  },
                ),
                _buildDropdown(
                  label: 'Dự án',
                  value: _selectedProject,
                  options: _projectOptions,
                  onChanged: (value) {
                    setState(() => _selectedProject = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                FilterChip(
                  selected: _onlyVideo,
                  onSelected: (value) => setState(() => _onlyVideo = value),
                  label: const Text('Có video'),
                ),
                FilterChip(
                  selected: _onlyQuiz,
                  onSelected: (value) => setState(() => _onlyQuiz = value),
                  label: const Text('Có quiz'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<_MetaOption> options,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String?>(
        isExpanded: true,
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text(
              'Tất cả',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...options.map(
            (option) => DropdownMenuItem<String?>(
              value: option.code,
              child: Text(
                option.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  final EduViHistoryEntry entry;
  final bool opening;
  final String Function(String iso) formatTime;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _HistoryEntryCard({
    required this.entry,
    required this.opening,
    required this.formatTime,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final blockEntries = entry.blockTypeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final isGame = entry.isGame;
    final isVideo = entry.isVideo;
    final legacyTechnicalTitle = RegExp(r'^game\s+[a-z0-9_]+$', caseSensitive: false);
    final normalizedPath = entry.filePath.replaceAll('\\', '/');
    final pathParts = normalizedPath.split('/').where((part) => part.isNotEmpty).toList();
    final fileName = pathParts.isEmpty ? entry.filePath : pathParts.last;
    final fallbackTitle = fileName.toLowerCase().endsWith('.eduvi')
        ? fileName.substring(0, fileName.length - '.eduvi'.length)
        : fileName;
    final displayTitle = (entry.title.trim().isEmpty || (isGame && legacyTechnicalTitle.hasMatch(entry.title.trim())))
        ? fallbackTitle
        : entry.title;
    final leadingIcon = isGame
      ? Icons.sports_esports_rounded
      : (isVideo ? Icons.ondemand_video_rounded : Icons.slideshow_rounded);
    final iconBg = isGame
      ? const Color(0xFFFFF7ED)
      : (isVideo ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF));
    final iconColor = isGame
      ? const Color(0xFFB45309)
      : (isVideo ? const Color(0xFFB91C1C) : const Color(0xFF2563EB));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(leadingIcon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayTitle,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatTime(entry.openedAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              entry.filePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isVideo || entry.slideCount > 0)
                  _TinyChip(label: 'Trang chiếu ${entry.slideCount}'),
                if (isVideo) const _TinyChip(label: 'Video package'),
                if (entry.hasVideo) const _TinyChip(label: 'Video'),
                if (entry.hasQuiz) const _TinyChip(label: 'Câu hỏi'),
                for (final item in blockEntries.take(4))
                  _TinyChip(label: '${item.key} ${item.value}'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: opening ? null : onOpen,
                  icon: opening
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Mở lại'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Xóa'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyChip extends StatelessWidget {
  final String label;

  const _TinyChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MetaOption {
  final String? code;
  final String name;

  const _MetaOption({required this.code, required this.name});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _MetaOption && other.code == code && other.name == name;
  }

  @override
  int get hashCode => Object.hash(code, name);
}
