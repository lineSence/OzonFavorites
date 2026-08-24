class ProductClassification {
  const ProductClassification({
    required this.categoryId,
    this.brand,
    this.productType,
    this.model,
    this.color,
    this.size,
    this.material,
    this.quantity,
    required this.confidence,
  });

  final String categoryId;
  final String? brand;
  final String? productType;
  final String? model;
  final String? color;
  final String? size;
  final String? material;
  final int? quantity;
  final double confidence;
}

/// Deterministic, offline product classifier.
///
/// This deliberately uses transparent rules and dictionaries rather than an
/// LLM. It is cheap, predictable, and easy to extend with new marketplace
/// vocabulary while the local AI layer is still disabled.
class ProductClassifier {
  static const _stopWords = <String>{
    'купить', 'заказать', 'доставка', 'скидка', 'акция', 'хит', 'топ',
    'новинка', 'оригинал', 'в наличии', 'руб', 'рублей', 'цена',
  };

  static const _brandWords = <String>{
    'apple', 'samsung', 'xiaomi', 'huawei', 'honor', 'sony', 'jbl', 'anker',
    'nike', 'adidas', 'puma', 'reebok', 'asics', 'new balance', 'lego',
    'logitech', 'razer', 'dyson', 'philips', 'bosch', 'tefal', 'ikea',
    'ozon', 'wildberries', 'baseus', 'ugreen', 'kingston', 'sandisk',
  };

  static const _categories = <String, List<String>>{
    'electronics': [
      'смартфон', 'телефон', 'планшет', 'ноутбук', 'компьютер', 'монитор',
      'телевизор', 'наушник', 'гарнитур', 'колонк', 'часы', 'смарт-часы',
      'клавиатур', 'мышь', 'геймпад', 'роутер', 'зарядк', 'пауэрбанк',
      'power bank', 'кабель', 'адаптер', 'флешк', 'ssd', 'hdd', 'видеокарт',
      'процессор', 'материнск', 'принтер', 'микрофон', 'камера',
    ],
    'clothing': [
      'футболк', 'майк', 'рубашк', 'свитер', 'толстовк', 'худи', 'джемпер',
      'куртк', 'пальто', 'пуховик', 'плащ', 'брюк', 'джинс', 'штан',
      'шорт', 'плать', 'юбк', 'бельё', 'носк', 'перчатк', 'шапк',
    ],
    'shoes': [
      'кроссовк', 'кед', 'ботин', 'сапог', 'туфл', 'босоножк', 'сланц',
      'тапоч', 'обувь', 'мокасин',
    ],
    'beauty': [
      'шампун', 'кондиционер', 'крем', 'сыворотк', 'маск', 'парфюм',
      'духи', 'туалетная вода', 'помад', 'тушь', 'тональн', 'космет',
      'дезодорант', 'гель для душа',
    ],
    'home': [
      'посуда', 'сковород', 'кастрюл', 'чайник', 'кофевар', 'пылесос',
      'утюг', 'одеял', 'подушк', 'постельн', 'полотенц', 'светильник',
      'ламп', 'мебель', 'стул', 'стол', 'шкаф', 'декор', 'контейнер',
    ],
    'sports': [
      'велосипед', 'самокат', 'гантел', 'тренажер', 'коврик', 'фитнес',
      'спортивн', 'турник', 'мяч', 'ракетк', 'лыж', 'коньк', 'рюкзак',
    ],
    'auto': [
      'автомобил', 'машин', 'авто', 'шина', 'диск колес', 'масло мотор',
      'фильтр салон', 'аккумулятор автомобиль', 'автозапчаст', 'держатель автомобиль',
    ],
    'kids': [
      'детск', 'ребён', 'ребен', 'игрушк', 'конструктор', 'кукл', 'коляск',
      'автокресл', 'пазл', 'настольная игра', 'lego',
    ],
    'tools': [
      'дрель', 'шуруповерт', 'перфоратор', 'лобзик', 'болгарк', 'инструмент',
      'отвертк', 'пассатиж', 'ключ гаечн', 'компрессор', 'сварочн',
    ],
    'food': [
      'кофе', 'чай', 'шоколад', 'печенье', 'макарон', 'крупа', 'конфет',
      'соус', 'специ', 'протеин', 'батончик', 'продукт',
    ],
  };

  static const _colors = <String, String>{
    'черн': 'чёрный', 'бел': 'белый', 'красн': 'красный', 'син': 'синий',
    'голуб': 'голубой', 'зелён': 'зелёный', 'зелен': 'зелёный', 'жёлт': 'жёлтый',
    'желт': 'жёлтый', 'сер': 'серый', 'розов': 'розовый', 'фиолет': 'фиолетовый',
    'корич': 'коричневый', 'беж': 'бежевый', 'оранж': 'оранжевый',
  };

  static const _materials = <String, String>{
    'хлопок': 'хлопок', 'кож': 'кожа', 'замш': 'замша', 'шерст': 'шерсть',
    'лен': 'лён', 'лён': 'лён', 'полиэстер': 'полиэстер', 'нейлон': 'нейлон',
    'пластик': 'пластик', 'металл': 'металл', 'алюмин': 'алюминий',
    'сталь': 'сталь', 'дерев': 'дерево', 'стекл': 'стекло', 'силикон': 'силикон',
  };

  ProductClassification classify(String input) {
    final text = _normalize(input);
    final categoryScores = <String, int>{};
    for (final entry in _categories.entries) {
      var score = 0;
      for (final keyword in entry.value) {
        if (text.contains(keyword)) score += keyword.length >= 7 ? 3 : 2;
      }
      if (score > 0) categoryScores[entry.key] = score;
    }

    final ranked = categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.isEmpty ? 'other' : ranked.first.key;
    final bestScore = ranked.isEmpty ? 0 : ranked.first.value;
    final secondScore = ranked.length > 1 ? ranked[1].value : 0;
    final confidence = best == 'other'
        ? 0.15
        : (0.55 + (bestScore * 0.07) + ((bestScore - secondScore).clamp(0, 4) * 0.05)).clamp(0.55, 0.99);

    final brand = _findBrand(text);
    final productType = _findProductType(text, best);
    final model = _findModel(input, brand, productType);
    final color = _findMapped(text, _colors);
    final material = _findMapped(text, _materials);
    final size = _findSize(input);
    final quantity = _findQuantity(input);

    return ProductClassification(
      categoryId: best,
      brand: brand,
      productType: productType,
      model: model,
      color: color,
      size: size,
      material: material,
      quantity: quantity,
      confidence: confidence,
    );
  }

  String _normalize(String value) {
    var text = value.toLowerCase().replaceAll('ё', 'е');
    for (final word in _stopWords) {
      text = text.replaceAll(word, ' ');
    }
    return text.replaceAll(RegExp(r'[^\p{L}\p{N}.+/-]+', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _findBrand(String text) {
    for (final brand in _brandWords) {
      if (text.contains(brand)) return brand == 'new balance' ? 'New Balance' : _titleCase(brand);
    }
    return null;
  }

  String? _findProductType(String text, String category) {
    final words = _categories[category] ?? const <String>[];
    for (final word in words) {
      if (text.contains(word)) return _humanizeType(word);
    }
    return null;
  }

  String? _findModel(String original, String? brand, String? type) {
    final cleaned = original.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (brand == null || type == null) return null;
    final pattern = RegExp('${RegExp.escape(brand)}\\s+(.{2,50})', caseSensitive: false);
    final match = pattern.firstMatch(cleaned);
    if (match == null) return null;
    final candidate = match.group(1)!.split(RegExp(r'[,;|]')).first.trim();
    return candidate.length <= 50 ? candidate : candidate.substring(0, 50).trim();
  }

  String? _findMapped(String text, Map<String, String> values) {
    for (final entry in values.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }

  String? _findSize(String input) {
    final match = RegExp(r'(?<!\d)(?:XXS|XS|S|M|L|XL|XXL|XXXL|\d{2}(?:[.,]\d)?)(?!\d)', caseSensitive: false).firstMatch(input);
    return match?.group(0)?.toUpperCase();
  }

  int? _findQuantity(String input) {
    final match = RegExp(r'(?:x|×|упаковка|комплект|набор|шт(?:\.|ук)?)[\s:]*(\d{1,3})', caseSensitive: false).firstMatch(input);
    return int.tryParse(match?.group(1) ?? '');
  }

  String _humanizeType(String value) {
    const map = {'смартфон': 'смартфон', 'футболк': 'футболка', 'кроссовк': 'кроссовки', 'шампун': 'шампунь', 'пылесос': 'пылесос'};
    return map[value] ?? value.replaceAll(RegExp(r'[ьъ]?$'), '');
  }

  String _titleCase(String value) => value.split(' ').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join(' ');
}
