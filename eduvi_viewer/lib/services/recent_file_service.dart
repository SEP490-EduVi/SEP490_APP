import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/eduvi_schema.dart';

const _lastOpenedEduViKey = 'last_opened_eduvi';

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

class RecentFileService {
  static Future<void> saveLastOpened({
    required String filePath,
    required EduViSchema schema,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = LastOpenedEduViInfo.fromSchema(filePath: filePath, schema: schema);
    await prefs.setString(_lastOpenedEduViKey, jsonEncode(payload.toJson()));
  }

  static Future<LastOpenedEduViInfo?> getLastOpened() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastOpenedEduViKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return LastOpenedEduViInfo.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
