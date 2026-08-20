import '../models/archive_item.dart';

class SmartSortResult {
  const SmartSortResult({
    required this.item,
    required this.category,
    required this.score,
    required this.matchedKeywords,
  });

  final ArchiveItem item;
  final String category;
  final double score;
  final List<String> matchedKeywords;

  bool get isConfident => score >= 0.45 && category != 'Другое';
}

/// Experimental, fully local classifier for the first smart-sorting MVP.
///
/// This is deliberately deterministic and does not use a network, embeddings,
/// or an LLM. It scores title/note/url tokens against a small taxonomy and
/// returns the best matching category.
class SmartSortService {
  static const Map<String, List<String>> _keywords = {
    'Одежда': [
      'футболк', 'майк', 'худи', 'толстовк', 'свитшот', 'куртк', 'пальто',
      'плащ', 'брюк', 'штаны', 'джинс', 'рубаш', 'плать', 'юбк', 'носк',
      'бель', 'одежд', 'кофт', 'свитер', 'жакет', 'жилет', 'шорт',
    ],
    'Обувь': [
      'кроссов', 'кед', 'ботин', 'сапог', 'туфл', 'сандал', 'сланц',
      'обув', 'крипер', 'тапоч',
    ],
    'Электроника': [
      'смартфон', 'телефон', 'iphone', 'android', 'ноутбук', 'планшет',
      'монитор', 'наушник', 'колонк', 'клавиатур', 'мыш', 'зарядк', 'кабел',
      'телевизор', 'камера', 'фотоаппарат', 'микрофон', 'роутер', 'ssd',
      'флешк', 'электрон', 'геймпад',
    ],
    'Дом': [
      'мебел', 'стол', 'стул', 'кресл', 'диван', 'кроват', 'шкаф', 'полк',
      'ламп', 'светильник', 'посуда', 'тарел', 'чашк', 'кухн', 'ванн',
      'интерьер', 'декор', 'подушк', 'матрас', 'штор', 'дом',
    ],
    'Инструменты': [
      'дрел', 'шуруповерт', 'перфоратор', 'болгарк', 'лобзик', 'пил',
      'молоток', 'отвертк', 'ключ', 'инструмент', 'сверл', 'крепеж',
      'компрессор', 'паяльник', 'мультиметр',
    ],
    'Игры': [
      'игр', 'steam', 'playstation', 'xbox', 'nintendo', 'switch', 'гейм',
      'gaming', 'rpg', 'minecraft', 'lego', 'консол',
    ],
    'Спорт': [
      'спорт', 'фитнес', 'тренаж', 'гантел', 'штанг', 'йог', 'бег',
      'велосипед', 'турник', 'мяч', 'баскетбол', 'футбол', 'лыж', 'сноуборд',
    ],
    'Красота': [
      'космет', 'шампун', 'крем', 'парфюм', 'дух', 'макияж', 'помад',
      'тушь', 'сыворотк', 'уход', 'волос', 'маникюр', 'бритв',
    ],
    'Авто': [
      'авто', 'автомобил', 'машин', 'шин', 'диск', 'масл', 'аккумулятор',
      'автозапчаст', 'фара', 'двигател', 'салон', 'багажник', 'мото',
    ],
  };

  List<SmartSortResult> classifyAll(Iterable<ArchiveItem> items) =>
      items.map(classify).toList(growable: false);

  SmartSortResult classify(ArchiveItem item) {
    final titleAndNote = _normalize('${item.title} ${item.note}');
    final url = _normalize(item.url);
    String bestCategory = 'Другое';
    var bestScore = 0.0;
    final bestMatches = <String>[];

    for (final entry in _keywords.entries) {
      final matches = <String>[];
      var titleAndNoteMatches = 0;
      var urlMatches = 0;

      for (final keyword in entry.value) {
        final normalizedKeyword = _normalize(keyword);
        if (titleAndNote.contains(normalizedKeyword)) {
          matches.add(keyword);
          titleAndNoteMatches++;
        } else if (url.contains(normalizedKeyword)) {
          matches.add(keyword);
          urlMatches++;
        }
      }
      if (matches.isEmpty) continue;

      final score = _score(
        titleAndNoteMatches: titleAndNoteMatches,
        urlMatches: urlMatches,
      );
      if (score > bestScore) {
        bestCategory = entry.key;
        bestScore = score;
        bestMatches
          ..clear()
          ..addAll(matches.take(4));
      }
    }

    return SmartSortResult(
      item: item,
      category: bestCategory,
      score: bestScore,
      matchedKeywords: List.unmodifiable(bestMatches),
    );
  }

  double _score({required int titleAndNoteMatches, required int urlMatches}) {
    if (titleAndNoteMatches >= 4) return 0.85;
    if (titleAndNoteMatches == 3) return 0.72;
    if (titleAndNoteMatches == 2) return 0.55;
    if (titleAndNoteMatches == 1) return urlMatches > 0 ? 0.55 : 0.55;
    if (urlMatches >= 4) return 0.85;
    if (urlMatches == 3) return 0.72;
    if (urlMatches == 2) return 0.55;
    return 0.35;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();
}
