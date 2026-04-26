import 'dart:convert';
import 'dart:typed_data';

import 'card_model.dart';

class EduViSchema {
  final String version;
  final String exportedAt;
  final EduViMetadata metadata;
  final List<EduViCard> cards;
  final List<EduViVideoTrack> videos;
  final Map<String, EduViAsset> assets;

  EduViSchema({
    required this.version,
    required this.exportedAt,
    required this.metadata,
    required this.cards,
    this.videos = const [],
    this.assets = const {},
  });

  factory EduViSchema.fromJson(Map<String, dynamic> json) {
    final metadataJson = Map<String, dynamic>.from(
      json['metadata'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
    metadataJson['packageType'] =
        metadataJson['packageType'] ?? json['packageType'];

    return EduViSchema(
      version: json['version'] as String? ?? '1.0.0',
      exportedAt: json['exportedAt'] as String? ?? '',
      metadata: EduViMetadata.fromJson(metadataJson),
      cards: (json['cards'] as List<dynamic>? ?? [])
        .map((c) => EduViCard.fromJson(c as Map<String, dynamic>))
        .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      videos: (json['videos'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(EduViVideoTrack.fromJson)
          .toList(),
      assets: (json['assets'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, EduViAsset.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }

  String get normalizedPackageType {
    final declared = (metadata.packageType ?? '').trim().toLowerCase();
    if (declared == 'slide' || declared == 'game' || declared == 'video') {
      return declared;
    }

    if (videos.isNotEmpty) {
      return 'video';
    }
    return 'slide';
  }

  bool get isVideoPackage => normalizedPackageType == 'video';
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
  final String? packageType;

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
    this.packageType,
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
      packageType: json['packageType'] as String?,
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

class EduViVideoTrack {
  final String productVideoCode;
  final String productCode;
  final String productName;
  final String status;
  final double duration;
  final String videoUrl;
  final String createdAt;
  final String updatedAt;
  final String completedAt;
  final List<EduViVideoInteraction> interactions;

  const EduViVideoTrack({
    required this.productVideoCode,
    required this.productCode,
    required this.productName,
    required this.status,
    required this.duration,
    required this.videoUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
    required this.interactions,
  });

  factory EduViVideoTrack.fromJson(Map<String, dynamic> json) {
    return EduViVideoTrack(
      productVideoCode: json['productVideoCode'] as String? ?? '',
      productCode: json['productCode'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      status: json['status'] as String? ?? '',
      duration: _toDouble(json['duration']),
      videoUrl: json['videoUrl'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      completedAt: json['completedAt'] as String? ?? '',
      interactions: (json['interactions'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(EduViVideoInteraction.fromJson)
          .toList()
        ..sort((a, b) => a.pauseTime.compareTo(b.pauseTime)),
    );
  }
}

class EduViVideoInteraction {
  final String type;
  final int slideIndex;
  final int cardIndex;
  final double startTime;
  final double endTime;
  final double pauseTime;
  final Map<String, dynamic> payload;

  const EduViVideoInteraction({
    required this.type,
    required this.slideIndex,
    required this.cardIndex,
    required this.startTime,
    required this.endTime,
    required this.pauseTime,
    required this.payload,
  });

  String get normalizedType => type.trim().toLowerCase();

  String get interactionId {
    return '${normalizedType}_${slideIndex}_${cardIndex}_${pauseTime.toStringAsFixed(3)}';
  }

  factory EduViVideoInteraction.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    final payload = rawPayload is Map<String, dynamic>
        ? rawPayload
        : rawPayload is Map
        ? rawPayload.map((k, v) => MapEntry('$k', v))
        : <String, dynamic>{};

    return EduViVideoInteraction(
      type: json['type'] as String? ?? '',
      slideIndex: _toInt(json['slide_index']),
      cardIndex: _toInt(json['card_index']),
      startTime: _toDouble(json['start_time']),
      endTime: _toDouble(json['end_time']),
      pauseTime: _toDouble(json['pause_time']),
      payload: payload,
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

int _toInt(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
