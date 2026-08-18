import '../models/price_point.dart';
import '../models/product.dart';
import '../repositories/product_repository.dart';
import 'product_importer.dart';

enum PriceUpdateStatus { updated, unchanged, noPrice, failed }

class PriceUpdateResult {
  const PriceUpdateResult(this.status, {this.oldPrice, this.newPrice});
  final PriceUpdateStatus status;
  final double? oldPrice;
  final double? newPrice;
}

/// Отслеживание цен: обновляет цену товара по его URL и сохраняет
/// точки в историю через [ProductRepository.recordPrice].
///
/// Работает локально и по запросу (без фоновых воркеров и серверов).
class PriceTracker {
  PriceTracker({required this.repository, ProductImporter? importer}) : importer = importer ?? ProductImporter();

  final ProductRepository repository;
  final ProductImporter importer;

  /// Проверяет актуальную цену товара. Если на странице есть цена —
  /// записывает точку в историю и обновляет товар.
  Future<PriceUpdateResult> updatePrice(Product product) async {
    try {
      final data = await importer.fetch(Uri.parse(product.url));
      final price = data.price;
      if (price == null) return const PriceUpdateResult(PriceUpdateStatus.noPrice);
      final currency = data.currency ?? product.currency;
      await repository.recordPrice(product, PricePoint(price: price, currency: currency, observedAt: DateTime.now()));
      if (product.price != null && product.price == price) {
        return PriceUpdateResult(PriceUpdateStatus.unchanged, oldPrice: product.price, newPrice: price);
      }
      return PriceUpdateResult(PriceUpdateStatus.updated, oldPrice: product.price, newPrice: price);
    } catch (_) {
      return const PriceUpdateResult(PriceUpdateStatus.failed);
    }
  }
}
