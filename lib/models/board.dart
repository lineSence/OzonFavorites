class Board {
  const Board({
    required this.id,
    required this.name,
    this.description = '',
    this.coverImageUrl,
    required this.createdAt,
    this.updatedAt,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String description;
  final String? coverImageUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int sortOrder;

  Board copyWith({
    String? name,
    String? description,
    Object? coverImageUrl = _unset,
    DateTime? updatedAt,
    int? sortOrder,
  }) => Board(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        coverImageUrl: coverImageUrl == _unset ? this.coverImageUrl : coverImageUrl as String?,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'coverImageUrl': coverImageUrl,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'sortOrder': sortOrder,
      };

  factory Board.fromJson(Map<String, dynamic> json) => Board(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Доска',
        description: json['description'] as String? ?? '',
        coverImageUrl: json['coverImageUrl'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

const _unset = Object();
