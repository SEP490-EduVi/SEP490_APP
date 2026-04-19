class EduViBlock {
  final String id;
  final String type;
  final int columnIndex;
  final int order;
  final Map<String, dynamic>? styles;
  final Map<String, dynamic> content;

  EduViBlock({
    required this.id,
    required this.type,
    required this.columnIndex,
    required this.order,
    this.styles,
    required this.content,
  });

  String get html => content['html'] as String? ?? '';
  String get src => content['src'] as String? ?? '';
  String get alt => content['alt'] as String? ?? '';
  int get headingLevel => content['level'] as int? ?? 2;
  bool get missingMedia => content['missingMedia'] as bool? ?? false;
  String get provider => content['provider'] as String? ?? 'direct';

  factory EduViBlock.fromJson(Map<String, dynamic> json) {
    return EduViBlock(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'TEXT',
      columnIndex: json['columnIndex'] as int? ?? 0,
      order: json['order'] as int? ?? 0,
      styles: json['styles'] as Map<String, dynamic>?,
      content: json['content'] as Map<String, dynamic>? ?? {},
    );
  }
}
