import '../models/archive_item.dart';
import 'product_features.dart';

class SmartSortResult {
  const SmartSortResult({
    required this.item,
    required this.category,
    required this.score,
    required this.matchedKeywords,
    required this.alternatives,
    required this.hasImageSignal,
  });

  final ArchiveItem item;
  final String category;
  final double score;
  final List<String> matchedKeywords;
  final List<SmartSortAlternative> alternatives;
  final bool hasImageSignal;

  bool get isConfident => score >= 0.45 && category != 'Другое';
  bool get needsReview => score < 0.45 || alternatives.isNotEmpty;
}

class SmartSortAlternative {
  const SmartSortAlternative({required this.category, required this.score});

  final String category;
  final double score;
}

/// Experimental local classifier for Smart Sort v2.
///
/// It is still deterministic and does not use a network, embeddings, or an
/// LLM. The important change is that classification is now based on a
/// normalized ProductFeatures object and returns top alternatives instead of
/// collapsing every uncertain item into "Другое".
class SmartSortService {
  static const Map<String, List<String>> _keywords = {
    'Одежда': [
      'футболк', 'майк', 'худи', 'толстовк', 'свитшот', 'куртк', 'пальто',
      'плащ', 'брюк', 'штаны', 'джинс', 'рубаш', 'плать', 'юбк', 'носк',
      'бель', 'одежд', 'кофт', 'свитер', 'жакет', 'жилет', 'шорт', 'толстовка',
    ],
    'Обувь': [
      'кроссов', 'кед', 'ботин', 'сапог', 'туфл', 'сандал', 'сланц',
      'обув', 'крипер', 'тапоч', 'мокасин', 'кросс',
    ],
    'Электроника': [
      'смартфон', 'телефон', 'iphone', 'android', 'ноутбук', 'планшет',
      'монитор', 'наушник', 'колонк', 'клавиатур', 'мыш', 'зарядк', 'кабел',
      'телевизор', 'камера', 'фотоаппарат', 'микрофон', 'роутер', 'ssd',
      'флешк', 'электрон', 'геймпад', 'пауэрбанк', 'powerbank', 'пк', 'компьютер',
    ],
    'Дом': [
      'мебел', 'стол', 'стул', 'кресл', 'диван', 'кроват', 'шкаф', 'полк',
      'ламп', 'светильник', 'посуда', 'тарел', 'чашк', 'кухн', 'ванн',
      'интерьер', 'декор', 'подушк', 'матрас', 'штор', 'дом', 'пылесос',
      'чайник', 'кофевар', 'блендер',
    ],
    'Инструменты': [
      'дрел', 'шуруповерт', 'перфоратор', 'болгарк', 'лобзик', 'пил',
      'молоток', 'отвертк', 'ключ', 'инструмент', 'сверл', 'крепеж',
      'компрессор', 'паяльник', 'мультиметр', 'набор инструмент',
    ],
    'Игры': [
      'игр', 'steam', 'playstation', 'xbox', 'nintendo', 'switch', 'гейм',
      'gaming', 'rpg', 'minecraft', 'lego', 'консол', 'game',
    ],
    'Спорт': [
      'спорт', 'фитнес', 'тренаж', 'гантел', 'штанг', 'йог', 'бег',
      'велосипед', 'турник', 'мяч', 'баскетбол', 'футбол', 'лыж', 'сноуборд',
      'эспандер', 'гимнаст',
    ],
    'Красота': [
      'космет', 'шампун', 'крем', 'парфюм', 'дух', 'макияж', 'помад',
      'тушь', 'сыворотк', 'уход', 'волос', 'маникюр', 'бритв', 'дезодорант',
    ],
    'Авто': [
      'авто', 'автомобил', 'машин', 'шин', 'диск', 'масл', 'аккумулятор',
      'автозапчаст', 'фара', 'двигател', 'салон', 'багажник', 'мото',
      'домкрат', 'автоаксессуар',
    ],
  };

  List<SmartSortResult> classifyAll(Iterable<ArchiveItem> items) =>
      items.map(classify).toList(growable: false);

  SmartSortResult classify(ArchiveItem item) => classifyFeatures(
        ProductFeatures.fromItem(item),
      );

  SmartSortResult classifyFeatures(ProductFeatures features) {
    final text = _normalize(features.text);
    final url = _normalize(features.url);
    final results = <String, _Candidate>{};

    for (final entry in _keywords.entries) {
      final matches = <String>[];
      var textMatches = 0;
      var urlMatches = 0;

      for (final keyword in entry.value) {
        final normalizedKeyword = _normalize(keyword);
        if (text.contains(normalizedKeyword)) {
          matches.add(keyword);
          textMatches++;
        } else if (url.contains(normalizedKeyword)) {
          matches.add(keyword);
          urlMatches++;
        }
      }

      if (matches.isEmpty) continue;
      results[entry.key] = _Candidate(
        score: _score(
          textMatches: textMatches,
          urlMatches: urlMatches,
          source: features.source,
        ),
        matches: matches.take(4).toList(growable: false),
      );
    }

    final ranked = results.entries.toList()
      ..sort((a, b) => b.value.score.compareTo(a.value.score));

    final best = ranked.isEmpty ? null : ranked.first;
    final alternatives = ranked
        .skip(1)
        .where((entry) => entry.value.score >= 0.30)
        .take(2)
        .map(
          (entry) => SmartSortAlternative(
            category: entry.key,
            score: entry.value.score,
          ),
        )
        .toList(growable: false);

    return SmartSortResult(
      item: features.item,
      category: best?.key ?? 'Другое',
      score: best?.value.score ?? 0,
      matchedKeywords: best?.value.matches ?? const [],
      alternatives: alternatives,
      hasImageSignal: features.hasImage,
    );
  }

  double _score({
    required int textMatches,
    required int urlMatches,
    required String source,
  }) {
    if (textMatches >= 4) return 0.92;
    if (textMatches == 3) return 0.82;
    if (textMatches == 2) return 0.68;
    if (textMatches == 1) return urlMatches > 0 ? 0.60 : 0.52;
    if (urlMatches >= 4) return 0.82;
    if (urlMatches == 3) return 0.72;
    if (urlMatches == 2) return 0.58;

    // Marketplace URLs are useful context, but should never turn a weak
    // single-token match into a high-confidence classification.
    if (urlMatches == 1 && source != 'unknown') return 0.42;
    return 0.35;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();
}

class _Candidate {
  const _Candidate({required this.score, required this.matches});

  final double score;
  final List<String> matches;
}
