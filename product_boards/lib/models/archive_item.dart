enum TitleSource { automatic, manual }

enum MetadataStatus { loading, success, partial, failed }

enum ImageStatus { loading, success, failed }

class ArchiveItem {
  const ArchiveItem({
    required this.id,
    required this.url,
    required this.title,
    required this.titleSource,
    this.imageUrl,
    required this.imageStatus,
    required this.note,
    required this.categoryId,
    required this.metadataStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String url;
  final String title;
  final TitleSource titleSource;
  final String? imageUrl;
  final ImageStatus imageStatus;
  final String note;
  final String? categoryId;
  final MetadataStatus metadataStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  ArchiveItem copyWith({
    String? url,
    String? title,
    TitleSource? titleSource,
    Object? imageUrl = _unset,
    ImageStatus? imageStatus,
    String? note,
    Object? categoryId = _unset,
    MetadataStatus? metadataStatus,
    DateTime? updatedAt,
  }) => ArchiveItem(
        id: id,
        url: url ?? this.url,
        title: title ?? this.title,
        titleSource: titleSource ?? this.titleSource,
        imageUrl: imageUrl == _unset ? this.imageUrl : imageUrl as String?,
        imageStatus: imageStatus ?? this.imageStatus,
        note: note ?? this.note,
        categoryId: categoryId == _unset ? this.categoryId : categoryId as String?,
        metadataStatus: metadataStatus ?? this.metadataStatus,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'titleSource': titleSource.name,
        'imageUrl': imageUrl,
        'imageStatus': imageStatus.name,
        'note': note,
        'categoryId': categoryId,
        'metadataStatus': metadataStatus.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ArchiveItem.fromJson(Map<String, dynamic> json) => ArchiveItem(
        id: json['id'] as String,
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? 'Без названия',
        titleSource: TitleSource.values.firstWhere(
          (e) => e.name == json['titleSource'],
          orElse: () => TitleSource.automatic,
        ),
        imageUrl: json['imageUrl'] as String?,
        imageStatus: ImageStatus.values.firstWhere(
          (e) => e.name == json['imageStatus'],
          orElse: () => json['imageUrl'] == null ? ImageStatus.failed : ImageStatus.success,
        ),
        note: json['note'] as String? ?? '',
        categoryId: json['categoryId'] as String?,
        metadataStatus: MetadataStatus.values.firstWhere(
          (e) => e.name == json['metadataStatus'],
          orElse: () => MetadataStatus.failed,
        ),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

const _unset = Object();
