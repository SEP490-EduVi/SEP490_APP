import 'block_model.dart';

class EduViLayout {
  final String id;
  final String variant;
  final int order;
  final List<double>? columnWidths;
  final List<EduViBlock> blocks;

  EduViLayout({
    required this.id,
    required this.variant,
    required this.order,
    this.columnWidths,
    required this.blocks,
  });

  int get columnCount {
    switch (variant) {
      case 'TWO_COLUMN':
      case 'SIDEBAR_LEFT':
      case 'SIDEBAR_RIGHT':
        return 2;
      case 'THREE_COLUMN':
        return 3;
      default:
        return 1;
    }
  }

  factory EduViLayout.fromJson(Map<String, dynamic> json) {
    return EduViLayout(
      id: json['id'] as String? ?? '',
      variant: json['variant'] as String? ?? 'SINGLE',
      order: json['order'] as int? ?? 0,
      columnWidths: (json['columnWidths'] as List<dynamic>?)
          ?.map((v) => (v as num).toDouble())
          .toList(),
      blocks: (json['blocks'] as List<dynamic>? ?? [])
        .map((b) => EduViBlock.fromJson(b as Map<String, dynamic>))
        .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }
}
