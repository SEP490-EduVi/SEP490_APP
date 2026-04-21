import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/eduvi_schema.dart';

const _lastOpenedEduViKey = 'last_opened_eduvi';
const _openHistoryEduViKey = 'eduvi_open_history_v2';
const _maxHistoryEntries = 200;

class LastOpenedEduViInfo {
  final String filePath;
  final String openedAt;
  final String title;
  final String description;
  final String createdAt;
  final String updatedAt;
  final String? projectCode;
  final String? projectName;
  final String? subjectCode;
  final String? subjectName;
  final String? gradeCode;
  final String? gradeName;

  LastOpenedEduViInfo({
    required this.filePath,
    required this.openedAt,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    this.projectCode,
    this.projectName,
    this.subjectCode,
    this.subjectName,
    this.gradeCode,
    this.gradeName,
  });

  factory LastOpenedEduViInfo.fromSchema({
    required String filePath,
    required EduViSchema schema,
  }) {
    return LastOpenedEduViInfo(
      filePath: filePath,
      openedAt: DateTime.now().toIso8601String(),
      title: schema.metadata.title,
      description: schema.metadata.description,
      createdAt: schema.metadata.createdAt,
      updatedAt: schema.metadata.updatedAt,
      projectCode: schema.metadata.projectCode,
      projectName: schema.metadata.projectName,
      subjectCode: schema.metadata.subjectCode,
      subjectName: schema.metadata.subjectName,
      gradeCode: schema.metadata.gradeCode,
      gradeName: schema.metadata.gradeName,
    );
  }

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'openedAt': openedAt,
    'title': title,
    'description': description,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'projectCode': projectCode,
    'projectName': projectName,
    'subjectCode': subjectCode,
    'subjectName': subjectName,
    'gradeCode': gradeCode,
    'gradeName': gradeName,
  };

  String toJsonString() => jsonEncode(toJson());

  factory LastOpenedEduViInfo.fromJson(Map<String, dynamic> json) {
    return LastOpenedEduViInfo(
      filePath: json['filePath'] as String? ?? '',
      openedAt: json['openedAt'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      projectCode: json['projectCode'] as String?,
      projectName: json['projectName'] as String?,
      subjectCode: json['subjectCode'] as String?,
      subjectName: json['subjectName'] as String?,
      gradeCode: json['gradeCode'] as String?,
      gradeName: json['gradeName'] as String?,
    );
  }
}

class EduViHistoryEntry {
  final String id;
  final String filePath;
  final String openedAt;
  final String title;
  final String description;
  final String createdAt;
  final String updatedAt;
  final String? projectCode;
  final String? projectName;
  final String? subjectCode;
  final String? subjectName;
  final String? gradeCode;
  final String? gradeName;
  final int slideCount;
  final Map<String, int> blockTypeCounts;
  final bool hasVideo;
  final bool hasQuiz;
  final String packageType;

  const EduViHistoryEntry({
    required this.id,
    required this.filePath,
    required this.openedAt,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    this.projectCode,
    this.projectName,
    this.subjectCode,
    this.subjectName,
    this.gradeCode,
    this.gradeName,
    required this.slideCount,
    required this.blockTypeCounts,
    required this.hasVideo,
    required this.hasQuiz,
    required this.packageType,
  });

  factory EduViHistoryEntry.fromSchema({
    required String filePath,
    required EduViSchema schema,
  }) {
    final stats = _HistoryStats.fromSchema(schema);
    return EduViHistoryEntry(
      id: _buildHistoryId(filePath),
      filePath: filePath,
      openedAt: DateTime.now().toIso8601String(),
      title: schema.metadata.title,
      description: schema.metadata.description,
      createdAt: schema.metadata.createdAt,
      updatedAt: schema.metadata.updatedAt,
      projectCode: schema.metadata.projectCode,
      projectName: schema.metadata.projectName,
      subjectCode: schema.metadata.subjectCode,
      subjectName: schema.metadata.subjectName,
      gradeCode: schema.metadata.gradeCode,
      gradeName: schema.metadata.gradeName,
      slideCount: schema.cards.length,
      blockTypeCounts: stats.blockTypeCounts,
      hasVideo: stats.hasVideo,
      hasQuiz: stats.hasQuiz,
      packageType: 'slide',
    );
  }

  factory EduViHistoryEntry.fromLegacy(LastOpenedEduViInfo legacy) {
    return EduViHistoryEntry(
      id: _buildHistoryId(legacy.filePath),
      filePath: legacy.filePath,
      openedAt: legacy.openedAt,
      title: legacy.title,
      description: legacy.description,
      createdAt: legacy.createdAt,
      updatedAt: legacy.updatedAt,
      projectCode: legacy.projectCode,
      projectName: legacy.projectName,
      subjectCode: legacy.subjectCode,
      subjectName: legacy.subjectName,
      gradeCode: legacy.gradeCode,
      gradeName: legacy.gradeName,
      slideCount: 0,
      blockTypeCounts: const {},
      hasVideo: false,
      hasQuiz: false,
      packageType: 'slide',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'openedAt': openedAt,
    'title': title,
    'description': description,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'projectCode': projectCode,
    'projectName': projectName,
    'subjectCode': subjectCode,
    'subjectName': subjectName,
    'gradeCode': gradeCode,
    'gradeName': gradeName,
    'slideCount': slideCount,
    'blockTypeCounts': blockTypeCounts,
    'hasVideo': hasVideo,
    'hasQuiz': hasQuiz,
    'packageType': packageType,
  };

  factory EduViHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['blockTypeCounts'];
    final counts = <String, int>{};
    if (rawCounts is Map) {
      for (final entry in rawCounts.entries) {
        final value = entry.value;
        if (value is num) {
          counts['${entry.key}'] = value.toInt();
        }
      }
    }

    return EduViHistoryEntry(
      id: json['id'] as String? ?? _buildHistoryId(json['filePath'] as String? ?? ''),
      filePath: json['filePath'] as String? ?? '',
      openedAt: json['openedAt'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      projectCode: json['projectCode'] as String?,
      projectName: json['projectName'] as String?,
      subjectCode: json['subjectCode'] as String?,
      subjectName: json['subjectName'] as String?,
      gradeCode: json['gradeCode'] as String?,
      gradeName: json['gradeName'] as String?,
      slideCount: (json['slideCount'] as num?)?.toInt() ?? 0,
      blockTypeCounts: counts,
      hasVideo: json['hasVideo'] as bool? ?? false,
      hasQuiz: json['hasQuiz'] as bool? ?? false,
      packageType: ((json['packageType'] as String?) ?? 'slide').toLowerCase(),
    );
  }

  bool get isGame => packageType == 'game';
}

class _HistoryStats {
  final Map<String, int> blockTypeCounts;
  final bool hasVideo;
  final bool hasQuiz;

  const _HistoryStats({
    required this.blockTypeCounts,
    required this.hasVideo,
    required this.hasQuiz,
  });

  factory _HistoryStats.fromSchema(EduViSchema schema) {
    final counts = <String, int>{};
    var hasVideo = false;
    var hasQuiz = false;

    for (final card in schema.cards) {
      if (card.isVideoSlide) {
        hasVideo = true;
      }

      for (final layout in card.layouts) {
        for (final block in layout.blocks) {
          final key = block.type.toUpperCase();
          counts.update(key, (value) => value + 1, ifAbsent: () => 1);

          if (key == 'VIDEO') {
            hasVideo = true;
          }
          if (key == 'QUIZ') {
            hasQuiz = true;
          }

          if (key == 'MATERIAL') {
            final widgetType = (block.content['widgetType'] as String? ?? '').toUpperCase();
            if (widgetType == 'MATERIAL_VIDEO' || widgetType == 'MATERIAL_YOUTUBE') {
              hasVideo = true;
            }
            if (widgetType == 'MATERIAL_QUIZ') {
              hasQuiz = true;
            }
          }
        }
      }
    }

    return _HistoryStats(
      blockTypeCounts: counts,
      hasVideo: hasVideo,
      hasQuiz: hasQuiz,
    );
  }
}

String _buildHistoryId(String filePath) {
  return '${DateTime.now().microsecondsSinceEpoch}_${filePath.hashCode}';
}

String _fallbackTitleFromPath(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return 'Game offline';
  }
  return parts.last;
}

class RecentFileService {
  static Future<void> saveLastOpened({
    required String filePath,
    required EduViSchema schema,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = LastOpenedEduViInfo.fromSchema(filePath: filePath, schema: schema);
    await prefs.setString(_lastOpenedEduViKey, payload.toJsonString());

    final history = await _readHistoryEntries(prefs);
    history.insert(0, EduViHistoryEntry.fromSchema(filePath: filePath, schema: schema));
    final trimmed = _trimHistory(history, _maxHistoryEntries);
    await _writeHistoryEntries(prefs, trimmed);
  }

  static Future<void> saveGameOpened({
    required String filePath,
    String? title,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await _readHistoryEntries(prefs);
    final now = DateTime.now().toIso8601String();

    history.insert(
      0,
      EduViHistoryEntry(
        id: _buildHistoryId(filePath),
        filePath: filePath,
        openedAt: now,
        title: (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : _fallbackTitleFromPath(filePath),
        description: 'Game offline',
        createdAt: now,
        updatedAt: now,
        slideCount: 0,
        blockTypeCounts: const {},
        hasVideo: false,
        hasQuiz: false,
        packageType: 'game',
      ),
    );

    final trimmed = _trimHistory(history, _maxHistoryEntries);
    await _writeHistoryEntries(prefs, trimmed);
  }

  static Future<LastOpenedEduViInfo?> getLastOpened() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastOpenedEduViKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        return LastOpenedEduViInfo.fromJson(json);
      } catch (_) {
        // Fall back to history payload below.
      }
    }

    final history = await getHistory(limit: 1);
    if (history.isEmpty) return null;
    final first = history.first;
    return LastOpenedEduViInfo(
      filePath: first.filePath,
      openedAt: first.openedAt,
      title: first.title,
      description: first.description,
      createdAt: first.createdAt,
      updatedAt: first.updatedAt,
      projectCode: first.projectCode,
      projectName: first.projectName,
      subjectCode: first.subjectCode,
      subjectName: first.subjectName,
      gradeCode: first.gradeCode,
      gradeName: first.gradeName,
    );
  }

  static Future<List<EduViHistoryEntry>> getHistory({int limit = _maxHistoryEntries}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await _readHistoryEntries(prefs);

    if (history.isEmpty) {
      final migrated = await _migrateLegacyToHistoryIfNeeded(prefs);
      if (migrated.isNotEmpty) {
        return migrated.take(limit).toList();
      }
    }

    return history.take(limit).toList();
  }

  static Future<void> removeHistoryEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await _readHistoryEntries(prefs);
    history.removeWhere((item) => item.id == entryId);
    await _writeHistoryEntries(prefs, history);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_openHistoryEduViKey);
  }

  static Future<List<EduViHistoryEntry>> _readHistoryEntries(SharedPreferences prefs) async {
    final raw = prefs.getString(_openHistoryEduViKey);
    if (raw == null || raw.isEmpty) return <EduViHistoryEntry>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <EduViHistoryEntry>[];

      final entries = <EduViHistoryEntry>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          entries.add(EduViHistoryEntry.fromJson(item));
        } else if (item is Map) {
          final converted = item.map((key, value) => MapEntry('$key', value));
          entries.add(EduViHistoryEntry.fromJson(converted));
        }
      }
      return entries;
    } catch (_) {
      return <EduViHistoryEntry>[];
    }
  }

  static Future<void> _writeHistoryEntries(
    SharedPreferences prefs,
    List<EduViHistoryEntry> entries,
  ) async {
    final payload = entries.map((item) => item.toJson()).toList();
    await prefs.setString(_openHistoryEduViKey, jsonEncode(payload));
  }

  static List<EduViHistoryEntry> _trimHistory(
    List<EduViHistoryEntry> entries,
    int maxEntries,
  ) {
    if (entries.length <= maxEntries) return entries;
    return entries.sublist(0, maxEntries);
  }

  static Future<List<EduViHistoryEntry>> _migrateLegacyToHistoryIfNeeded(
    SharedPreferences prefs,
  ) async {
    final rawLegacy = prefs.getString(_lastOpenedEduViKey);
    if (rawLegacy == null || rawLegacy.isEmpty) return <EduViHistoryEntry>[];

    try {
      final decoded = jsonDecode(rawLegacy) as Map<String, dynamic>;
      final legacy = LastOpenedEduViInfo.fromJson(decoded);
      final migrated = <EduViHistoryEntry>[EduViHistoryEntry.fromLegacy(legacy)];
      await _writeHistoryEntries(prefs, migrated);
      return migrated;
    } catch (_) {
      return <EduViHistoryEntry>[];
    }
  }
}
