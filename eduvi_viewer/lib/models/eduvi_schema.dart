import 'dart:convert';
import 'dart:typed_data';

import 'card_model.dart';

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
      metadata: EduViMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>? ?? {},
      ),
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
  final String createdAt;
  final String updatedAt;
  final String? projectCode;
  final String? projectName;
  final String? subjectCode;
  final String? subjectName;
  final String? gradeCode;
  final String? gradeName;

  EduViMetadata({
    required this.title,
    this.description = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.projectCode,
    this.projectName,
    this.subjectCode,
    this.subjectName,
    this.gradeCode,
    this.gradeName,
  });

  factory EduViMetadata.fromJson(Map<String, dynamic> json) {
    return EduViMetadata(
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
