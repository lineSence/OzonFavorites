import '../models/archive_item.dart';
import '../models/category.dart';

abstract class ArchiveRepository {
  Future<void> init();
  String newId();
  Future<List<ArchiveItem>> getItems({String? categoryId});
  Future<ArchiveItem?> getItem(String id);
  Future<List<ArchiveItem>> findByNormalizedUrl(String normalizedUrl);
  Future<void> upsertItem(ArchiveItem item);
  Future<void> deleteItem(String id);
  Future<void> deleteItems(Iterable<String> ids);
  Future<void> assignCategory(Iterable<String> ids, String? categoryId);
  Future<List<Category>> getCategories();
  Future<Category?> getCategory(String id);
  Future<Category?> findCategoryByName(String name);
  Future<void> upsertCategory(Category category);
  Future<void> deleteCategory(String id);
  Future<void> close();
}
