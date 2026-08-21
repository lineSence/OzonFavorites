import '../models/archive_item.dart';
import 'product_features.dart';

class SmartSortResult {
  const SmartSortResult({required this.item, required this.category, required this.score, required this.matchedKeywords, required this.alternatives, required this.hasImageSignal});

  final ArchiveItem item;
  final String category;
  final double score;
  final List<String> matchedKeywords;
  final List<SmartSortAlternative> alternatives;
  final bool hasImageSignal;

  bool get isConfident => score >= .50 && category != 'Другое';
  bool get needsReview => score < .50 || alternatives.isNotEmpty;
}

class SmartSortAlternative {
  const SmartSortAlternative({required this.category, required this.score});
  final String category;
  final double score;
}

/// Deterministic offline classifier. It is deliberately isolated from the UI
/// and domain model so a future embedding/vision classifier can replace it.
class SmartSortService {
  static const Map<String, List<String>> _keywords = {
    'Одежда': ['футболк', 'майк', 'худи', 'толстовк', 'свитшот', 'куртк', 'пальто', 'плащ', 'брюк', 'штаны', 'джинс', 'рубаш', 'плать', 'юбк', 'носк', 'бель', 'одежд', 'кофт', 'свитер', 'жакет', 'жилет', 'шорт', 'топ', 'леггинс', 'спортивк', 'ветровк', 'парка', 'кардиган', 'пиджак', 'комбинезон', 'костюм', 'флис', 'лонгслив', 'поло', 'боди'],
    'Обувь': ['кроссов', 'кед', 'ботин', 'сапог', 'туфл', 'сандал', 'сланц', 'обув', 'тапоч', 'мокасин', 'шлепан', 'угги', 'балетк', 'полуботин', 'босонож'],
    'Электроника': ['смартфон', 'телефон', 'iphone', 'android', 'ноутбук', 'ультрабук', 'планшет', 'монитор', 'наушник', 'колонк', 'клавиатур', 'мыш', 'зарядк', 'кабел', 'телевиз', 'камера', 'фотоаппарат', 'микрофон', 'роутер', 'модем', 'ssd', 'hdd', 'флешк', 'электрон', 'геймпад', 'пауэрбанк', 'powerbank', 'компьютер', 'видеокарт', 'процессор', 'принтер', 'сканер', 'проектор', 'умные часы', 'смарт часы', 'приставк', 'консол'],
    'Дом': ['мебел', 'стол', 'стул', 'кресл', 'диван', 'кроват', 'шкаф', 'полк', 'ламп', 'светильник', 'посуда', 'тарел', 'чашк', 'кухн', 'ванн', 'интерьер', 'декор', 'подушк', 'матрас', 'штор', 'пылесос', 'чайник', 'кофевар', 'блендер', 'микроволн', 'духовк', 'мультиварк', 'утюг', 'увлажнител', 'органайзер', 'постель', 'полотенц', 'зеркал', 'ваза', 'сковород', 'кастрюл'],
    'Инструменты': ['дрел', 'шуруповерт', 'перфоратор', 'болгарк', 'лобзик', 'пил', 'молоток', 'отвертк', 'инструмент', 'сверл', 'крепеж', 'компрессор', 'паяльник', 'мультиметр', 'стремянк', 'уровень', 'рулетк', 'тиск', 'шлифмаш', 'фрезер', 'краскопульт'],
    'Игры': ['steam', 'playstation', 'xbox', 'nintendo', 'switch', 'гейм', 'gaming', 'rpg', 'minecraft', 'lego', 'консол', 'game', 'игровой', 'игр', 'настольн игра', 'карточная игр', 'пазл', 'головоломк'],
    'Спорт': ['спорт', 'фитнес', 'тренаж', 'гантел', 'штанг', 'йог', 'бег', 'велосипед', 'турник', 'мяч', 'баскетбол', 'футбол', 'лыж', 'сноуборд', 'эспандер', 'гимнаст', 'скейтборд', 'самокат', 'коньк', 'ракетк', 'теннис', 'рыбалк', 'удочк', 'палатк', 'спальник', 'туризм'],
    'Красота': ['космет', 'шампун', 'крем', 'парфюм', 'дух', 'макияж', 'помад', 'тушь', 'сыворотк', 'уход', 'волос', 'маникюр', 'бритв', 'дезодорант', 'гель для душа', 'скраб', 'тональн', 'румян', 'лак для ногтей', 'фен', 'плойк', 'стайлер', 'эпилятор', 'зубная щетк'],
    'Авто': ['авто', 'автомобил', 'машин', 'шин', 'диск', 'масл', 'аккумулятор', 'автозапчаст', 'фара', 'двигател', 'багажник', 'мото', 'домкрат', 'автоаксессуар', 'видеорегистратор', 'автоковрик'],
    'Канцелярия': ['канцеляр', 'ручк', 'карандаш', 'маркер', 'фломастер', 'тетрад', 'блокнот', 'ежедневник', 'скетчбук', 'бумаг', 'папк', 'степлер', 'скрепк', 'клей', 'ластик', 'линейк', 'пенал', 'краск', 'акварел', 'гуашь', 'кисточк', 'чернил', 'дневник'],
    'Книги': ['книг', 'роман', 'учебник', 'манг', 'комикс', 'энциклопед', 'литератур', 'бестселлер', 'артбук', 'пособие', 'справочник', 'атлас', 'альбом'],
    'Детское': ['детск', 'ребенк', 'малыш', 'младен', 'для девоч', 'для мальчик', 'погремуш', 'коляск', 'автокресло детск', 'игрушк', 'конструктор', 'кукл', 'плюшев'],
    'Зоотовары': ['для собак', 'для кошек', 'кот', 'собак', 'кошач', 'корм для', 'наполнител', 'ошейник', 'поводок', 'лежанк', 'когтеточк', 'переноск', 'аквариум', 'зоотовар'],
    'Сад и дача': ['сад', 'дач', 'газон', 'семен', 'рассад', 'горшок', 'теплиц', 'полив', 'шланг', 'секатор', 'лопат', 'грабл', 'удобр', 'мангал', 'гриль', 'барбекю', 'садовый'],
    'Строительство и ремонт': ['строй', 'ремонт', 'цемент', 'шпатлевк', 'штукатур', 'грунтовк', 'краск', 'эмаль', 'герметик', 'монтажн', 'профил', 'гипсокартон', 'плитк', 'линолеум', 'обои', 'утеплител', 'метиз', 'саморез', 'дюбел', 'розетк', 'выключател'],
    'Музыка': ['гитар', 'бас-гитар', 'скрипк', 'пианин', 'синтезатор', 'микрофон', 'усилител', 'педал', 'миди', 'midi', 'музыкальн', 'барабан', 'струн', 'медиатор', 'ноты', 'аккорд'],
    'Хобби и творчество': ['для творчества', 'рукодел', 'вязани', 'шить', 'вышивк', 'бисер', 'фетр', 'моделирован', 'модель', 'миниатюр', 'макет', 'выжиган', 'лепк', 'эпоксид', 'скрапбукинг', 'оригами', 'аэрограф', 'граффити', 'трафарет'],
    'Аксессуары': ['сумк', 'рюкзак', 'кошелек', 'портмоне', 'ремень', 'перчатк', 'шарф', 'шапк', 'кепк', 'панам', 'галстук', 'зонт', 'очк', 'солнцезащитн', 'чехол', 'брелок', 'часы', 'бижутер', 'серьг', 'кольц', 'браслет'],
    'Продукты': ['продукт', 'кофе', 'чай', 'шоколад', 'сладост', 'печень', 'конфет', 'бакале', 'специ', 'соус', 'круп', 'макарон', 'консерв', 'протеин', 'батончик', 'витамин', 'минерал'],
  };

  static const Map<String, Map<String, double>> _phrases = {
    'Обувь': {'спортивная обувь': 1.0, 'мужская обувь': .9, 'женская обувь': .9, 'кроссовки мужские': 1.0, 'кроссовки женские': 1.0},
    'Одежда': {'верхняя одежда': 1.0, 'мужская одежда': .9, 'женская одежда': .9, 'спортивная одежда': .9},
    'Электроника': {'беспроводные наушники': 1.0, 'смарт часы': .9, 'умные часы': .9, 'игровая приставка': 1.0, 'видеокарта': 1.0},
    'Дом': {'бытовая техника': 1.0, 'кухонная техника': 1.0, 'товары для дома': .9},
    'Строительство и ремонт': {'строительные материалы': 1.0, 'отделочные материалы': 1.0},
  };

  static const Map<String, List<String>> _negative = {
    'Игры': ['игровой стол', 'игровое кресло', 'игровой монитор'],
    'Спорт': ['спортивная куртка', 'спортивная одежда'],
  };

  SmartSortResult classify(ArchiveItem item) {
    final features = ProductFeatures.fromItem(item);
    final text = _buildSearchText(features);
    final scores = <String, double>{};
    final matches = <String, List<String>>{};

    for (final entry in _keywords.entries) {
      var score = 0.0;
      final found = <String>[];
      for (final keyword in entry.value) {
        final normalized = _normalize(keyword);
        if (text.contains(normalized)) {
          score += normalized.contains(' ') ? 1.25 : 1.0;
          found.add(keyword);
        }
      }
      for (final phrase in _phrases[entry.key]?.entries ?? const <MapEntry<String, double>>[]) {
        if (text.contains(_normalize(phrase.key))) {
          score += 2.0 * phrase.value;
          found.add(phrase.key);
        }
      }
      for (final negative in _negative[entry.key] ?? const <String>[]) {
        if (text.contains(_normalize(negative))) score -= 2.5;
      }
      if (score > 0) {
        scores[entry.key] = score;
        matches[entry.key] = found;
      }
    }

    if (scores.isEmpty) return SmartSortResult(item: item, category: 'Другое', score: 0, matchedKeywords: const [], alternatives: const [], hasImageSignal: features.hasImage);

    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first;
    final second = ranked.length > 1 ? ranked[1] : null;
    final normalizedScore = (top.value / (top.value + (second?.value ?? 0) + .5)).clamp(0.0, .98).toDouble();
    final alternatives = ranked.skip(1).take(2).map((e) => SmartSortAlternative(category: e.key, score: (e.value / (top.value + .5)).clamp(0.0, .99).toDouble())).toList();

    return SmartSortResult(item: item, category: top.key, score: normalizedScore, matchedKeywords: matches[top.key] ?? const [], alternatives: alternatives, hasImageSignal: features.hasImage);
  }

  static String _buildSearchText(ProductFeatures features) {
    final uri = Uri.tryParse(features.url);
    final path = uri?.path ?? features.url;
    final decodedPath = Uri.decodeComponent(path);
    return _normalize('${features.text} $decodedPath');
  }

  static String _normalize(String value) => value.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
