import '../models/board.dart';
import '../models/price_point.dart';
import '../models/product.dart';
import '../models/tag.dart';

/// Абстракция хранилища данных приложения.
///
/// Единственная текущая реализация — [LocalRepository] (SQLite).
/// Интерфейс оставлен как задел под будущую синхронизацию/облачное
/// хранилище: UI работает с [ProductRepository], а не с конкретным
/// классом.
abstract class ProductRepository {
  Future<void> init();

  Future<List<Product>> getProducts();
  Future<List<Board>> getBoards();

  Future<void> upsertProduct(Product product);
  Future<void> deleteProduct(String id);
  Future<void> upsertBoard(Board board);
  Future<void> deleteBoard(String id);

  Future<List<Tag>> getTags();
  Future<void> saveTags(List<Tag> tags);
  Future<void> deleteTag(String id);

  Future<List<PricePoint>> getPriceHistory(String productId);
  Future<void> recordPrice(Product product, PricePoint point);

  Future<Map<String, dynamic>> exportData();
  Future<void> importData(Map<String, dynamic> data);

  String newId();
  Future<void> close();
}
