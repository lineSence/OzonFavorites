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
    this.tagIds = const [],
    this.boardIds = const [],
    this.status = ProductStatus.wishlist,
    this.priority = 0,
    this.quantity = 1,
    this.comparisonUrl,
    this.desiredPurchaseDate,
    this.lastCheckedAt,
    this.priceLowest,
    this.priceDrop,
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
  /// id вложенных тегов ([Tag]), связанных с товаром.
  final List<String> tagIds;
  final List<String> boardIds;
  final ProductStatus status;
  final int priority;
  final int quantity;
  /// Ссылка для сравнения цен (если есть).
  final String? comparisonUrl;
  /// Желаемая дата покупки (если есть).
  final DateTime? desiredPurchaseDate;
  /// Когда цена последний раз проверялась/обновлялась.
  final DateTime? lastCheckedAt;
  /// Наблюдаемый минимальный уровень цены.
  final double? priceLowest;
  /// True, если при последней проверке цена оказалась ниже предыдущей.
  final bool? priceDrop;

  Product copyWith({
    String? url,
    String? source,
    String? title,
    Object? imageUrl = _unset,
    Object? price = _unset,
    String? currency,
    DateTime? updatedAt,
    String? note,
    List<String>? tagIds,
    List<String>? boardIds,
    ProductStatus? status,
    int? priority,
    int? quantity,
    Object? comparisonUrl = _unset,
    Object? desiredPurchaseDate = _unset,
    Object? lastCheckedAt = _unset,
    Object? priceLowest = _unset,
    Object? priceDrop = _unset,
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
      tagIds: List.unmodifiable(tagIds ?? this.tagIds),
      boardIds: List.unmodifiable(boardIds ?? this.boardIds),
      status: status ?? this.status,
      priority: priority ?? this.priority,
      quantity: quantity ?? this.quantity,
      comparisonUrl: comparisonUrl == _unset ? this.comparisonUrl : comparisonUrl as String?,
      desiredPurchaseDate: desiredPurchaseDate == _unset ? this.desiredPurchaseDate : desiredPurchaseDate as DateTime?,
      lastCheckedAt: lastCheckedAt == _unset ? this.lastCheckedAt : lastCheckedAt as DateTime?,
      priceLowest: priceLowest == _unset ? this.priceLowest : priceLowest as double?,
      priceDrop: priceDrop == _unset ? this.priceDrop : priceDrop as bool?,
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
        'tagIds': tagIds,
        'boardIds': boardIds,
        'status': status.name,
        'priority': priority,
        'quantity': quantity,
        'comparisonUrl': comparisonUrl,
        'desiredPurchaseDate': desiredPurchaseDate?.toIso8601String(),
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'priceLowest': priceLowest,
        'priceDrop': priceDrop,
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
        tagIds: _readTagIds(json),
        boardIds: List<String>.from(json['boardIds'] as List? ?? const []),
        status: ProductStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => ProductStatus.wishlist,
        ),
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        comparisonUrl: json['comparisonUrl'] as String?,
        desiredPurchaseDate: DateTime.tryParse(json['desiredPurchaseDate'] as String? ?? ''),
        lastCheckedAt: DateTime.tryParse(json['lastCheckedAt'] as String? ?? ''),
        priceLowest: (json['priceLowest'] as num?)?.toDouble(),
        priceDrop: json['priceDrop'] as bool?,
      );
}

/// Читает список id тегов. Старый формат ('tags' — плоские имена строк)
/// мигрируется в сущность Tag на уровне БД; здесь он игнорируется.
List<String> _readTagIds(Map<String, dynamic> json) {
  final tagIds = json['tagIds'];
  if (tagIds is List) return List<String>.from(tagIds.map((e) => e.toString()));
  return const [];
}

const _unset = Object();

enum ProductStatus { wishlist, considering, purchased, archived }
