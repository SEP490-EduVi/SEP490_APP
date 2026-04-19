import 'package:flutter/material.dart';

import 'layout_model.dart';

class EduViCard {
  final String id;
  final String title;
  final int order;
  final Color? backgroundColor;
  final String? backgroundImage;
  final String contentAlignment;
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
      id: json['id'] as String? ?? '',
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
