class Product {
  const Product({
    required this.id,
    required this.url,
    required this.source,
    required this.title,
    this.imageUrl,
    this.price,
    this.currency = '₽',
    required this.createdAt,
    this.updatedAt,
    this.note = '',
    this.tags = const [],
    this.boardIds = const [],
    this.status = ProductStatus.wishlist,
    this.priority = 0,
  });

  final String id;
  final String url;
  final String source;
  final String title;
  final String? imageUrl;
  final double? price;
  final String currency;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String note;
  final List<String> tags;
  final List<String> boardIds;
  final ProductStatus status;
  final int priority;

  Product copyWith({
    String? url,
    String? source,
    String? title,
    Object? imageUrl = _unset,
    Object? price = _unset,
    String? currency,
    DateTime? updatedAt,
    String? note,
    List<String>? tags,
    List<String>? boardIds,
    ProductStatus? status,
    int? priority,
  }) {
    return Product(
      id: id,
      url: url ?? this.url,
      source: source ?? this.source,
      title: title ?? this.title,
      imageUrl: imageUrl == _unset ? this.imageUrl : imageUrl as String?,
      price: price == _unset ? this.price : price as double?,
      currency: currency ?? this.currency,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      note: note ?? this.note,
      tags: List.unmodifiable(tags ?? this.tags),
      boardIds: List.unmodifiable(boardIds ?? this.boardIds),
      status: status ?? this.status,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'source': source,
        'title': title,
        'imageUrl': imageUrl,
        'price': price,
        'currency': currency,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'note': note,
        'tags': tags,
        'boardIds': boardIds,
        'status': status.name,
        'priority': priority,
      };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        url: json['url'] as String? ?? '',
        source: json['source'] as String? ?? 'Other',
        title: json['title'] as String? ?? 'Без названия',
        imageUrl: json['imageUrl'] as String?,
        price: (json['price'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? '₽',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        note: json['note'] as String? ?? '',
        tags: List<String>.from(json['tags'] as List? ?? const []),
        boardIds: List<String>.from(json['boardIds'] as List? ?? const []),
        status: ProductStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => ProductStatus.wishlist,
        ),
        priority: (json['priority'] as num?)?.toInt() ?? 0,
      );
}

const _unset = Object();

enum ProductStatus { wishlist, considering, purchased, archived }
