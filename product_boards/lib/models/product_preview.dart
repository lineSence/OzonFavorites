class ProductPreview {
  const ProductPreview({
    required this.url,
    required this.title,
    this.description,
    this.imageUrl,
    this.localImageUri,
    this.price,
    this.currency = '₽',
    required this.siteName,
  });

  final Uri url;
  final String title;
  final String? description;
  final String? imageUrl;
  final String? localImageUri;
  final double? price;
  final String currency;
  final String siteName;

  String? get image => localImageUri ?? imageUrl;
}
