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

  bool get isConfident => score >= 0.50 && category != 'Другое';
  bool get needsReview => score < 0.50 || alternatives.isNotEmpty;
}

class SmartSortAlternative {
  const SmartSortAlternative({required this.category, required this.score});

  final String category;
  final double score;
}

/// Experimental local classifier for Smart Sort v3.
///
/// This version is still fully offline and deterministic. It deliberately does
/// not pretend that keywords are embeddings: instead it improves recall with
/// aliases, product phrases, URL decoding, weighted evidence and contradiction
/// penalties. The API is kept ready for a future embedding/vision backend.
class SmartSortService {
  static const Map<String, List<String>> _keywords = {
    'Одежда': [
      'футболк', 'майк', 'худи', 'толстовк', 'свитшот', 'куртк', 'пальто',
      'плащ', 'брюк', 'штаны', 'джинс', 'рубаш', 'плать', 'юбк', 'носк',
      'бель', 'одежд', 'кофт', 'свитер', 'жакет', 'жилет', 'шорт', 'топ',
      'леггинс', 'спортивк', 'ветровк', 'парка', 'кардиган', 'пиджак',
      'комбинезон', 'костюм', 'флис', 'лонгслив', 'поло', 'боди', 'халат',
    ],
    'Обувь': [
      'кроссов', 'кед', 'ботин', 'сапог', 'туфл', 'сандал', 'сланц',
      'обув', 'тапоч', 'мокасин', 'шлепан', 'угги', 'балетк', 'полуботин',
      'берц', 'чешк', 'босонож',
    ],
    'Электроника': [
      'смартфон', 'телефон', 'iphone', 'android', 'ноутбук', 'ультрабук',
      'планшет', 'электронная книг', 'монитор', 'наушник', 'колонк',
      'клавиатур', 'мыш', 'зарядк', 'кабел', 'телевизор', 'телевиз', 'камера',
      'фотоаппарат', 'микрофон', 'роутер', 'модем', 'ssd', 'hdd', 'флешк',
      'электрон', 'геймпад', 'пауэрбанк', 'powerbank', 'пк', 'компьютер',
      'видеокарт', 'процессор', 'материнск', 'оперативн', 'принтер', 'сканер',
      'проектор', 'умные часы', 'смарт часы', 'часы', 'приставк', 'консол',
      'webcam', 'веб камер', 'акустик', 'саундбар', 'усилител', 'диктофон',
    ],
    'Дом': [
      'мебел', 'стол', 'стул', 'кресл', 'диван', 'кроват', 'шкаф', 'полк',
      'ламп', 'светильник', 'посуда', 'тарел', 'чашк', 'кухн', 'ванн',
      'интерьер', 'декор', 'подушк', 'матрас', 'штор', 'пылесос', 'чайник',
      'кофевар', 'блендер', 'микроволн', 'духовк', 'мультиварк', 'утюг',
      'отпаривател', 'сушилк', 'увлажнител', 'очистител воздуха', 'ведр',
      'контейнер', 'органайзер', 'постель', 'полотенц', 'зеркал', 'ваза',
      'сервиз', 'сковород', 'кастрюл', 'нож кухон',
    ],
    'Инструменты': [
      'дрел', 'шуруповерт', 'перфоратор', 'болгарк', 'лобзик', 'пил',
      'молоток', 'отвертк', 'ключ', 'инструмент', 'сверл', 'крепеж',
      'компрессор', 'паяльник', 'мультиметр', 'стремянк', 'уровень',
      'рулетк', 'тесак', 'стусл', 'тиск', 'шлифмаш', 'фрезер', 'краскопульт',
    ],
    'Игры': [
      'steam', 'playstation', 'xbox', 'nintendo', 'switch', 'гейм', 'gaming',
      'rpg', 'minecraft', 'lego', 'консол', 'game', 'игровой', 'игр',
      'настольн игра', 'настольная игр', 'карточная игр', 'пазл', 'головоломк',
    ],
    'Спорт': [
      'спорт', 'фитнес', 'тренаж', 'гантел', 'штанг', 'йог', 'бег', 'велосипед',
      'турник', 'мяч', 'баскетбол', 'футбол', 'лыж', 'сноуборд', 'эспандер',
      'гимнаст', 'ролик', 'скейтборд', 'самокат', 'коньк', 'ракетк', 'теннис',
      'бадминтон', 'рыбалк', 'удочк', 'палатк', 'спальник', 'туризм',
    ],
    'Красота': [
      'космет', 'шампун', 'крем', 'парфюм', 'дух', 'макияж', 'помад', 'тушь',
      'сыворотк', 'уход', 'волос', 'маникюр', 'бритв', 'дезодорант', 'гель для душа',
      'кондиционер для волос', 'маск для волос', 'скраб', 'тональн', 'румян',
      'лак для ногтей', 'фен', 'плойк', 'стайлер', 'эпилятор', 'зубная щетк',
    ],
    'Авто': [
      'авто', 'автомобил', 'машин', 'шин', 'диск', 'масл', 'аккумулятор',
      'автозапчаст', 'фара', 'двигател', 'салон', 'багажник', 'мото',
      'домкрат', 'автоаксессуар', 'щетк стекло', 'видеорегистратор',
      'автоковрик', 'органайзер в багажник', 'компрессор автомобиль',
    ],
    'Канцелярия': [
      'канцеляр', 'ручк', 'карандаш', 'маркер', 'фломастер', 'тетрад', 'блокнот',
      'ежедневник', 'скетчбук', 'бумаг', 'папк', 'степлер', 'скрепк', 'клей',
      'ластик', 'линейк', 'пенал', 'органайзер', 'краск', 'акварел', 'гуашь',
      'кисточк', 'чернил', 'письм', 'дневник',
    ],
    'Книги': [
      'книг', 'роман', 'учебник', 'манг', 'комикс', 'энциклопед', 'литератур',
      'бестселлер', 'артбук', 'пособие', 'справочник', 'атлас', 'альбом',
    ],
    'Детское': [
      'детск', 'ребенк', 'малыш', 'младен', 'для девоч', 'для мальчик',
      'погремуш', 'коляск', 'автокресло детск', 'детское кресло', 'игрушк',
      'конструктор', 'кукл', 'плюшев', 'радиоуправляем', 'детский велосипед',
    ],
    'Зоотовары': [
      'для собак', 'для кошек', 'кот', 'собак', 'кошач', 'корм для', 'наполнител',
      'ошейник', 'поводок', 'лежанк', 'когтеточк', 'переноск', 'аквариум',
      'зоотовар', 'ветеринар',
    ],
    'Сад и дача': [
      'сад', 'дач', 'газон', 'семен', 'рассад', 'горшок', 'теплиц', 'полив',
      'шланг', 'секатор', 'лопат', 'грабл', 'тяпк', 'удобр', 'мангал', 'гриль',
      'барбекю', 'садовый', 'тепличн',
    ],
    'Строительство и ремонт': [
      'строй', 'ремонт', 'цемент', 'шпатлевк', 'штукатур', 'грунтовк', 'краск',
      'эмаль', 'герметик', 'монтажн', 'профил', 'гипсокартон', 'плитк', 'линолеум',
      'обои', 'утеплител', 'пен', 'метиз', 'саморез', 'дюбел', 'розетк', 'выключател',
    ],
    'Музыка': [
      'гитар', 'бас-гитар', 'скрипк', 'пианин', 'синтезатор', 'микрофон',
      'усилител', 'педал', 'миди', 'midi', 'музыкальн', 'барабан', 'струн',
      'медиатор', 'каподастр', 'ноты', 'аккорд',
    ],
    'Хобби и творчество': [
      'для творчества', 'рукодел', 'вязани', 'шить', 'вышивк', 'бисер', 'фетр',
      'моделирован', 'модель', 'миниатюр', 'макет', 'выжиган', 'лепк', 'пластик',
      'эпоксид', 'скрапбукинг', 'оригами', 'аэрограф', 'граффити', 'трафарет',
    ],
    'Аксессуары': [
      'сумк', 'рюкзак', 'кошелек', 'портмоне', 'ремень', 'перчатк', 'шарф',
      'шапк', 'кепк', 'панам', 'галстук', 'зонт', 'очк', 'солнцезащитн',
      'чехол', 'брелок', 'часы', 'бижутер', 'серьг', 'кольц', 'браслет', 'цепочк',
    ],
    'Продукты': [
      'продукт', 'кофе', 'чай', 'шоколад', 'сладост', 'печень', 'конфет',
      'бакале', 'специ', 'соус', 'масл оливков', 'круп', 'макарон', 'консерв',
      'протеин', 'батончик', 'витамин', 'минерал',
    ],
  };

  /// Phrases whose meaning is much stronger than an individual token.
  static const Map<String, Map<String, double>> _phrases = {
    'Обувь': {
      'спортивная обувь': 1.0,
      'мужская обувь': 0.9,
      'женская обувь': 0.9,
      'детская обувь': 0.9,
      'кроссовки мужские': 1.0,
      'кроссовки женские': 1.0,
    },
    'Одежда': {
      'верхняя одежда': 1.0,
      'мужская одежда': 0.9,
      'женская одежда': 0.9,
      'спортивная одежда': 0.9,
    },
    'Электроника': {
      'беспроводные наушники': 1.0,
      'смарт часы': 0.9,
      'умные часы': 0.9,
      'игровая приставка': 1.0,
      'видеокарта': 1.0,
    },
    'Дом': {
      'бытовая техника': 1.0,
      'кухонная техника': 1.0,
      'товары для дома': 0.9,
    },
    'Строительство и ремонт': {
      'строительные материалы': 1.0,
      'отделочные материалы': 1.0,
    },
  };

  static const Map<String, List<String>> _negative = {
    'Игры': ['игровой стол', 'игровое кресло', 'игровой монитор'],
    'Спорт': ['спортивный костюм', 'спортивная куртка', 'спортивная обувь'],
    'Аксессуары': ['аксессуары для авто', 'аксессуары для телефона'],
  };

  List<SmartSortResult> classifyAll(Iterable<ArchiveItem> items) =>
      items.map(classify).toList(growable: false);

  SmartSortResult classify(ArchiveItem item) => classifyFeatures(
        ProductFeatures.fromItem(item),
      );

  SmartSortResult classifyFeatures(ProductFeatures features) {
    final text = _normalize(features.text);
    final decodedUrl = _decodeUrl(features.url);
    final url = _normalize(decodedUrl);
    final combined = '$text $url'.trim();
    final results = <String, _Candidate>{};

    for (final entry in _keywords.entries) {
      var weightedHits = 0.0;
      final matches = <String>[];
      var textHits = 0;
      var urlHits = 0;

      for (final keyword in entry.value) {
        final normalizedKeyword = _normalize(keyword);
        if (normalizedKeyword.isEmpty) continue;

        final inText = _containsTerm(text, normalizedKeyword);
        final inUrl = !inText && _containsTerm(url, normalizedKeyword);
        if (!inText && !inUrl) continue;

        matches.add(keyword);
        if (inText) {
          textHits++;
          weightedHits += _keywordWeight(normalizedKeyword, text);
        } else {
          urlHits++;
          weightedHits += 0.45;
        }
      }

      for (final phraseEntry in _phrases[entry.key]?.entries ?? const <MapEntry<String, double>>[]) {
        if (_containsTerm(combined, _normalize(phraseEntry.key))) {
          weightedHits += 2.5 * phraseEntry.value;
          matches.add(phraseEntry.key);
          textHits++;
        }
      }

      if (weightedHits <= 0) continue;

      var score = _score(
        weightedHits: weightedHits,
        textMatches: textHits,
        urlMatches: urlHits,
        source: features.source,
      );

      for (final negative in _negative[entry.key] ?? const <String>[]) {
        if (_containsTerm(text, _normalize(negative))) {
          score -= 0.25;
        }
      }

      if (score > 0) {
        results[entry.key] = _Candidate(
          score: score.clamp(0.0, 0.98),
          matches: matches.take(5).toList(growable: false),
        );
      }
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
    required double weightedHits,
    required int textMatches,
    required int urlMatches,
    required String source,
  }) {
    var score = 0.28 + weightedHits * 0.16;
    if (textMatches > 0) score += 0.06;
    if (textMatches >= 2) score += 0.08;
    if (textMatches >= 3) score += 0.08;
    if (urlMatches > 0) score += source == 'unknown' ? 0.02 : 0.04;
    return score.clamp(0.0, 0.98);
  }

  double _keywordWeight(String keyword, String text) {
    // Exact product phrases are more informative than generic category words.
    if (keyword.length >= 10) return 1.35;
    if (keyword.length >= 7) return 1.15;
    if (text.split(' ').contains(keyword)) return 1.10;
    return 0.90;
  }

  bool _containsTerm(String text, String term) {
    if (term.contains(' ')) return text.contains(term);
    return RegExp(r'(^|\s)' + RegExp.escape(term) + r'[a-zа-я0-9]*($|\s)').hasMatch(text) ||
        text.contains(term);
  }

  String _decodeUrl(String value) {
    try {
      return Uri.decodeFull(value.replaceAll(RegExp(r'[+_]'), ' '));
    } catch (_) {
      return value.replaceAll(RegExp(r'[+_]'), ' ');
    }
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _Candidate {
  const _Candidate({required this.score, required this.matches});

  final double score;
  final List<String> matches;
}
