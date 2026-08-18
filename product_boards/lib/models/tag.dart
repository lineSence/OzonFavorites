/// Вложенный тег (иерархия через [parentId]).
class Tag {
  const Tag({required this.id, required this.name, this.color, this.parentId});

  final String id;
  final String name;
  /// Hex-цвет в формате `#RRGGBB` (опционально).
  final String? color;
  /// id родительского тега для вложенной иерархии.
  final String? parentId;

  Tag copyWith({
    String? name,
    Object? color = _unset,
    Object? parentId = _unset,
  }) => Tag(
        id: id,
        name: name ?? this.name,
        color: color == _unset ? this.color : color as String?,
        parentId: parentId == _unset ? this.parentId : parentId as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'parentId': parentId,
      };

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Тег',
        color: json['color'] as String?,
        parentId: json['parentId'] as String?,
      );
}

const _unset = Object();
