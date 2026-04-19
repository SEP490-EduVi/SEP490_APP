import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/block_model.dart';
import '../../services/asset_service.dart';
import 'video_block_widget.dart';

class MaterialBlockWidget extends StatelessWidget {
  final EduViBlock block;
  final AssetService assetService;
  final bool presentationMode;
  final bool isActiveSlide;

  const MaterialBlockWidget({
    super.key,
    required this.block,
    required this.assetService,
    this.presentationMode = false,
    this.isActiveSlide = true,
  });

  Map<String, dynamic> get _data {
    final raw = block.content['data'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry('$k', v));
    return const <String, dynamic>{};
  }

  String get _widgetType =>
      (block.content['widgetType'] as String? ?? '').toUpperCase();

  @override
  Widget build(BuildContext context) {
    switch (_widgetType) {
      case 'MATERIAL_VIDEO':
        return _buildVideoMaterial();
      case 'MATERIAL_CODE':
        return _buildCodeMaterial();
      case 'MATERIAL_CHART':
        return _buildChartMaterial();
      case 'MATERIAL_QUIZ':
        return _buildQuizMaterial();
      case 'MATERIAL_PDF':
        return _buildInfoCard();
      case 'MATERIAL_YOUTUBE':
        return const SizedBox.shrink();
      case 'MATERIAL_AUDIO':
      case 'MATERIAL_EMBED':
        return _buildInfoCard();
      default:
        return _buildInfoCard(showJson: true);
    }
  }

  Widget _buildVideoMaterial() {
    final src = (_data['src'] as String? ?? '').trim();
    if (src.isEmpty) return _buildInfoCard();

    final videoBlock = EduViBlock(
      id: '${block.id}-material-video',
      type: 'VIDEO',
      columnIndex: block.columnIndex,
      order: block.order,
      styles: block.styles,
      content: {
        'type': 'VIDEO',
        'src': src,
        'provider': (_data['provider'] as String? ?? 'direct'),
      },
    );

    return VideoBlockWidget(
      block: videoBlock,
      assetService: assetService,
      presentationMode: presentationMode,
      isActiveSlide: isActiveSlide,
    );
  }

  Widget _buildCodeMaterial() {
    final code = (_data['code'] as String? ?? '').trim();
    final language = (_data['language'] as String? ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language.isNotEmpty) ...[
            Text(
              language.toUpperCase(),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
            const SizedBox(height: 8),
          ],
          SelectableText(
            code.isEmpty ? '(empty code)' : code,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontFamily: 'Consolas',
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartMaterial() {
    final rawData = _data['data'];
    final points = <Map<String, dynamic>>[];

    if (rawData is List) {
      for (final item in rawData) {
        if (item is Map<String, dynamic>) {
          points.add(item);
        } else if (item is Map) {
          points.add(item.map((k, v) => MapEntry('$k', v)));
        }
      }
    }

    if (points.isEmpty) return _buildInfoCard();

    var maxValue = 0.0;
    for (final point in points) {
      final v = (point['value'] as num?)?.toDouble() ?? 0;
      if (v > maxValue) maxValue = v;
    }
    if (maxValue <= 0) maxValue = 1;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final point in points) ...[
            Text(
              (point['label'] as String? ?? 'item'),
              style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
            ),
            const SizedBox(height: 4),
            FractionallySizedBox(
              widthFactor:
                  ((point['value'] as num?)?.toDouble() ?? 0) / maxValue,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildQuizMaterial() {
    final questions = _data['questions'];
    final title = (_data['title'] as String? ?? 'Quiz').trim();

    var count = 0;
    if (questions is List) count = questions.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.quiz, color: Color(0xFF2563EB), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$title${count > 0 ? ' - $count câu hỏi' : ''}',
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({bool showJson = false}) {
    final src = (_data['src'] as String? ?? _data['url'] as String? ?? '')
        .trim();
    final title = (_data['title'] as String? ?? _widgetType).trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? _widgetType : title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (src.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              src,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (showJson) ...[
            const SizedBox(height: 10),
            Text(
              const JsonEncoder.withIndent('  ').convert(_data),
              style: const TextStyle(color: Color(0xFF475569), fontSize: 11),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
