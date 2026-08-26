class ProductClassification {
  const ProductClassification({required this.categoryId, this.subcategoryId, this.brand, this.productType, this.model, this.color, this.size, this.material, this.quantity, required this.confidence, this.alternatives = const <ClassificationAlternative>[]});
  final String categoryId;
  final String? subcategoryId;
  final String? brand;
  final String? productType;
  final String? model;
  final String? color;
  final String? size;
  final String? material;
  final int? quantity;
  final double confidence;
  final List<ClassificationAlternative> alternatives;
}
class ClassificationAlternative { const ClassificationAlternative(this.categoryId, this.score); final String categoryId; final double score; }
class ProductClassifier {
  static const _stopWords = <String>{'купить','заказать','доставка','скидка','акция','хит','топ','новинка','оригинал','в наличии','руб','рублей','цена','от производителя'};
  static const _brands = <String,String>{'apple':'Apple','samsung':'Samsung','xiaomi':'Xiaomi','huawei':'Huawei','honor':'Honor','sony':'Sony','jbl':'JBL','anker':'Anker','nike':'Nike','adidas':'Adidas','puma':'Puma','reebok':'Reebok','asics':'ASICS','new balance':'New Balance','lego':'LEGO','logitech':'Logitech','razer':'Razer','dyson':'Dyson','philips':'Philips','bosch':'Bosch','tefal':'Tefal','ikea':'IKEA','baseus':'Baseus','ugreen':'UGREEN','kingston':'Kingston','sandisk':'SanDisk'};
  static const _categories = <String,List<String>>{
    'electronics':['смартфон','телефон','планшет','ноутбук','компьютер','монитор','телевизор','наушник','гарнитур','колонк','часы','клавиатур','мышь','геймпад','роутер','зарядк','пауэрбанк','power bank','кабель','адаптер','флешк','ssd','hdd','видеокарт','процессор','материнск','принтер','микрофон','камера'],
    'clothing':['футболк','майк','рубашк','свитер','толстовк','худи','джемпер','куртк','пальто','пуховик','плащ','брюк','джинс','штан','шорт','плать','юбк','бельё','носк','перчатк','шапк'],
    'shoes':['кроссовк','кед','ботин','сапог','туфл','босоножк','сланц','тапоч','обувь','мокасин'],
    'beauty':['шампун','кондиционер','крем','сыворотк','маск','парфюм','духи','туалетная вода','помад','тушь','тональн','космет','дезодорант','гель для душа'],
    'home':['посуда','сковород','кастрюл','чайник','кофевар','пылесос','утюг','одеял','подушк','постельн','полотенц','светильник','ламп','мебель','стул','стол','шкаф','декор','контейнер'],
    'sports':['велосипед','самокат','гантел','тренажер','коврик','фитнес','спортивн','турник','мяч','ракетк','лыж','коньк','рюкзак'],
    'auto':['автомобил','машин','авто','шина','диск колес','масло мотор','фильтр салон','аккумулятор автомобиль','автозапчаст','держатель автомобиль'],
    'kids':['детск','ребён','ребен','игрушк','конструктор','кукл','коляск','автокресл','пазл','настольная игра','lego'],
    'tools':['дрель','шуруповерт','перфоратор','лобзик','болгарк','инструмент','отвертк','пассатиж','ключ гаечн','компрессор','сварочн'],
    'food':['кофе','чай','шоколад','печенье','макарон','крупа','конфет','соус','специ','протеин','батончик','продукт']};
  static const _types = <String,List<String>>{'electronics/audio':['наушник','гарнитур','tws','earbud','headphone','headset'],'electronics/mobile':['смартфон','телефон','iphone','galaxy','pixel'],'electronics/computers':['ноутбук','компьютер','монитор','клавиатур','мышь','ssd','hdd'],'electronics/accessories':['чехол','стекло','плёнка','кабель','переходник','адаптер','зарядк'],'clothing/tshirts':['футболк','t-shirt','tee'],'clothing/outerwear':['куртк','пуховик','пальто','парка'],'shoes/sneakers':['кроссовк','sneaker','кед'],'beauty/hair':['шампун','кондиционер','маска для волос'],'home/kitchen':['сковород','кастрюл','посуда','чайник','кофевар'],'sports/fitness':['гантел','тренажер','коврик','турник']};
  static const _negative = <String,List<String>>{'electronics/audio':['чехол','кейс','футляр'],'electronics/mobile':['чехол','стекло','плёнка','кабель'],'shoes/sneakers':['крем','щётка','стелька','шнурк']};
  static const _colors = <String,String>{'черн':'чёрный','бел':'белый','красн':'красный','син':'синий','голуб':'голубой','зелён':'зелёный','зелен':'зелёный','жёлт':'жёлтый','желт':'жёлтый','сер':'серый','розов':'розовый','фиолет':'фиолетовый','корич':'коричневый','беж':'бежевый','оранж':'оранжевый'};
  static const _materials = <String,String>{'хлопок':'хлопок','кож':'кожа','замш':'замша','шерст':'шерсть','лен':'лён','лён':'лён','полиэстер':'полиэстер','нейлон':'нейлон','пластик':'пластик','металл':'металл','алюмин':'алюминий','сталь':'сталь','дерев':'дерево','стекл':'стекло','силикон':'силикон'};
  ProductClassification classify(String input) {
    final text = _normalize(input); final scores=<String,int>{};
    for (final entry in _categories.entries) { var score=0; for (final keyword in entry.value) { if (text.contains(keyword)) { score += keyword.length>=7 ? 4 : 2; } } if (score>0) { scores[entry.key]=score; } }
    final typeScores=<String,int>{};
    for (final entry in _types.entries) { var score=0; for (final keyword in entry.value) { if (text.contains(keyword)) { score += keyword.length>=7 ? 6 : 4; } } for (final negative in _negative[entry.key] ?? const <String>[]) { if (text.contains(negative)) { score-=8; } } if (score>0) { typeScores[entry.key]=score; } }
    final ranked=scores.entries.toList()..sort((a,b)=>b.value.compareTo(a.value)); final typeRanked=typeScores.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
    final bestCategory=ranked.isEmpty?'other':ranked.first.key; final bestType=typeRanked.isEmpty?null:typeRanked.first.key; final resolvedCategory=bestType?.split('/').first??bestCategory;
    final bestScore=typeRanked.isNotEmpty?typeRanked.first.value:(ranked.isEmpty?0:ranked.first.value); final secondScore=typeRanked.length>1?typeRanked[1].value:(ranked.length>1?ranked[1].value:0); final gap=(bestScore-secondScore).clamp(0,8); final confidence=resolvedCategory=='other'?0.15:(0.52+bestScore*0.045+gap*0.035).clamp(0.52,0.99);
    final alternatives=<ClassificationAlternative>[]; for (final entry in (typeRanked.isNotEmpty?typeRanked:ranked)) { final id=entry.key; if (id==(bestType??bestCategory)) { continue; } alternatives.add(ClassificationAlternative(id,(entry.value/(bestScore==0?1:bestScore)).clamp(0.0,0.99))); if (alternatives.length==2) { break; } }
    final brand=_findBrand(text); final productType=bestType==null?_findBroadType(text,resolvedCategory):bestType.split('/').last;
    return ProductClassification(categoryId:resolvedCategory,subcategoryId:bestType,brand:brand,productType:productType,model:_findModel(input,brand),color:_findMapped(text,_colors),material:_findMapped(text,_materials),size:_findSize(input),quantity:_findQuantity(input),confidence:confidence,alternatives:alternatives);
  }
  String _normalize(String value) { var text=value.toLowerCase().replaceAll('ё','е'); for (final word in _stopWords) { text=text.replaceAll(word,' '); } return text.replaceAll(RegExp(r'[^\p{L}\p{N}.+/-]+',unicode:true),' ').replaceAll(RegExp(r'\s+'),' ').trim(); }
  String? _findBrand(String text) { for (final entry in _brands.entries) { if (text.contains(entry.key)) { return entry.value; } } return null; }
  String? _findBroadType(String text,String category) { for (final keyword in _categories[category]??const <String>[]) { if (text.contains(keyword)) { return keyword; } } return null; }
  String? _findModel(String original,String? brand) { if (brand==null) return null; final match=RegExp('${RegExp.escape(brand)}\\s+(.{2,60})',caseSensitive:false).firstMatch(original.replaceAll(RegExp(r'\s+'),' ')); if (match==null) return null; final candidate=match.group(1)!.split(RegExp(r'[,;|]')).first.trim(); return candidate.length<=60?candidate:candidate.substring(0,60).trim(); }
  String? _findMapped(String text,Map<String,String> values) { for (final entry in values.entries) { if (text.contains(entry.key)) { return entry.value; } } return null; }
  String? _findSize(String input)=>RegExp(r'(?<!\d)(?:XXXS|XXS|XS|S|M|L|XL|XXL|XXXL|\d{2}(?:[.,]\d)?)(?!\d)',caseSensitive:false).firstMatch(input)?.group(0)?.toUpperCase();
  int? _findQuantity(String input)=>int.tryParse(RegExp(r'(?:x|×|упаковка|комплект|набор|шт(?:\.|ук)?)[\s:]*(\d{1,3})',caseSensitive:false).firstMatch(input)?.group(1)??'');
}
