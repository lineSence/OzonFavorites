# Pinzon — техническая документация

> Актуальное состояние исходного кода на ветке `main` по состоянию на 20 августа 2026 года.
>
> Документ описывает **фактически реализованную архитектуру**, а не целевую архитектуру продукта. Если README и код расходятся, источником истины для этого документа считается текущий код проекта.

## 1. Назначение проекта

**Pinzon** — Android-приложение для локального визуального архива ссылок/товаров. Основной сценарий — получить ссылку через системное меню Android «Поделиться», сохранить её в локальный архив, попытаться автоматически получить название и изображение, а затем дать пользователю возможность вручную отредактировать карточку и разложить её по подборкам.

Ключевые архитектурные свойства текущего MVP:

- Flutter UI + Dart business logic;
- Android-native Kotlin bridge для Share Intent и WebView;
- offline-first хранение данных;
- SQLite через `sqflite`;
- отсутствие собственного backend/API;
- автоматический импорт метаданных с несколькими fallback-стратегиями;
- локальный кэш изображений;
- отдельная очередь фоновой обработки метаданных;
- диагностический журнал для проблем импорта изображений;
- GitHub Actions для Android-сборки.

---

## 2. Текущее состояние и границы MVP

### Реализовано

1. Приём `http/https` URL через Android Share Intent.
2. Cold start и hot start обработки Share Intent.
3. Добавление ссылки вручную из UI.
4. Проверка дубликатов по нормализованному URL.
5. Локальное хранение карточек и подборок в SQLite.
6. CRUD для подборок.
7. Перемещение одной или нескольких карточек между подборками.
8. Удаление одной или нескольких карточек.
9. Редактирование карточки.
10. Асинхронное получение title/image/price/description.
11. HTML metadata / JSON-LD fallback.
12. Android WebView fallback для маркетплейсов.
13. Скриншот WebView как основной источник изображения для marketplace fallback.
14. Специальная стратегия поиска Ozon-карточки по названию для коротких Ozon-ссылок.
15. Локальный кэш изображений.
16. Диагностика стадий импорта и отдельный экран диагностики изображений.
17. Повторные попытки получения метаданных.
18. Миграция legacy-структуры `products`/`boards` в текущую схему `archive_items`/`categories`.
19. Release APK/AAB сборка через GitHub Actions.

### Не считать частью текущего надёжного контракта

Следующие возможности упоминаются в историческом README, но не должны считаться источником истины без проверки текущего кода:

- теги как отдельная сущность;
- история цен;
- автоматическое отслеживание цен;
- сложная система приоритетов/статусов;
- облачная синхронизация;
- backend/API;
- AI-сортировка.

Текущая модель `ArchiveItem` содержит только URL, title, изображение, заметку, подборку, статусы и timestamps.

---

## 3. Репозиторий и структура

Корень репозитория: `lineSence/OzonFavorites`.

Фактический Flutter-проект находится во вложенной директории `product_boards/`.

```text
OzonFavorites/
├── .github/
│   └── workflows/
│       └── build-android.yml
└── product_boards/
    ├── android/
    │   ├── app/
    │   │   ├── build.gradle.kts
    │   │   └── src/main/
    │   │       ├── AndroidManifest.xml
    │   │       └── kotlin/com/example/productboards/MainActivity.kt
    │   ├── build.gradle.kts
    │   ├── gradle.properties
    │   ├── gradle/wrapper/
    │   ├── key.properties.example
    │   └── settings.gradle.kts
    ├── lib/
    │   ├── main.dart
    │   ├── models/
    │   │   ├── archive_item.dart
    │   │   ├── category.dart
    │   │   └── product_preview.dart
    │   ├── repositories/
    │   │   ├── archive_repository.dart
    │   │   └── local_archive_repository.dart
    │   ├── screens/
    │   │   └── image_diagnostics_screen.dart
    │   ├── services/
    │   │   ├── image_cache_service.dart
    │   │   ├── image_diagnostics.dart
    │   │   ├── marketplace_search_resolver.dart
    │   │   ├── metadata_queue.dart
    │   │   ├── metadata_service.dart
    │   │   ├── product_importer.dart
    │   │   ├── product_preview_resolver.dart
    │   │   └── url_normalizer.dart
    │   └── widgets/
    │       └── product_preview_image.dart
    ├── test/
    │   ├── archive_item_test.dart
    │   ├── product_importer_test.dart
    │   └── url_normalizer_test.dart
    ├── scripts/
    ├── analysis_options.yaml
    ├── pubspec.yaml
    └── README.md
```

---

## 4. Технологический стек

| Слой | Технология | Назначение |
|---|---|---|
| UI | Flutter / Dart | интерфейс и состояние экранов |
| Native Android | Kotlin | Share Intent, WebView, screenshot, MethodChannel |
| Persistence | SQLite + `sqflite` | локальная БД |
| Files | Android application documents/cache storage | локальные изображения |
| HTTP | `http` | загрузка HTML/изображений/search pages |
| HTML | `html` | разбор HTML и metadata |
| IDs | `uuid` | UUID карточек/подборок |
| URL | `url_launcher` | открытие исходной ссылки |
| Share | `share_plus` + native Share Intent | системный обмен |
| Preferences | `shared_preferences` | вспомогательные локальные настройки, если используются |
| Hashing | `crypto` | имена файлов image cache |
| Paths | `path`, `path_provider` | файловая система |
| Grid | `flutter_staggered_grid_view` | masonry/Pinterest-like UI |
| Tests | `flutter_test`, `sqflite_common_ffi` | unit/widget и локальные DB-тесты |

### Версии

Из `pubspec.yaml`:

- Flutter: `>=3.38.1`;
- Dart SDK: `>=3.10.0 <4.0.0`;
- Android Java/Kotlin target: Java 17;
- Android `minSdk`: 24;
- `applicationId`: `com.example.productboards`.

CI фиксирует Flutter `3.38.1` и Gradle `8.13`.

---

## 5. Архитектура приложения

Архитектуру текущего MVP удобно рассматривать как пять уровней:

```text
┌─────────────────────────────────────────────┐
│ Flutter UI                                  │
│ main.dart / screens / widgets               │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│ Domain/application flow                     │
│ MetadataQueue / ProductPreviewResolver      │
└───────────────┬─────────────────┬───────────┘
                │                 │
                ▼                 ▼
┌───────────────────────┐  ┌───────────────────┐
│ Import / network      │  │ Local storage     │
│ ProductImporter       │  │ ArchiveRepository │
│ MetadataService       │  │ SQLite            │
│ SearchResolver        │  └───────────────────┘
└───────────┬───────────┘
            │
            ▼
┌─────────────────────────────────────────────┐
│ Android native bridge                       │
│ MainActivity.kt / WebView / Share Intent    │
└─────────────────────────────────────────────┘
```

### Главная особенность

Flutter не пытается сам реализовать Android Share/WebView-поведение. Android предоставляет два native entry points через один `MethodChannel`:

```text
product_boards/share
```

Методы:

- `getInitialSharedData` — получить Share Intent, полученный до запуска Flutter;
- `sharedData` — push-событие для hot start;
- `resolveProduct` — попросить native WebView открыть URL и вернуть результат импорта.

---

## 6. Точка входа Flutter

`lib/main.dart` выполняет следующие действия:

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. Создаёт `LocalArchiveRepository`.
3. Выполняет `repository.init()`.
4. Создаёт `MetadataQueue`.
5. Запускает `queue.resumePending()` без блокировки UI.
6. Запускает `PinzonApp`.

Это означает, что восстановление незавершённых metadata jobs происходит после запуска приложения.

### Основной экран

`ArchiveScreen` отвечает за:

- загрузку категорий и карточек;
- фильтрацию по подборке;
- добавление URL;
- обработку входящего Share Intent;
- создание/переименование/удаление подборок;
- одиночное и массовое перемещение;
- одиночное и массовое удаление;
- открытие редактора и карточки товара;
- обновление UI после завершения импорта.

Текущий `main.dart` остаётся крупным orchestration-файлом. Это допустимо для MVP, но является главным кандидатом на дальнейшее разбиение.

---

## 7. Модель данных

### `ArchiveItem`

Файл: `lib/models/archive_item.dart`.

```text
ArchiveItem
├── id: String
├── url: String
├── title: String
├── titleSource: automatic | manual
├── imageUrl: String?
├── imageStatus: loading | success | failed
├── note: String
├── categoryId: String?
├── metadataStatus: loading | success | partial | failed
├── createdAt: DateTime
└── updatedAt: DateTime
```

Изображение хранится не как бинарные данные SQLite, а как URI локального файла.

### `Category`

Подборка имеет:

- UUID;
- название;
- `createdAt`;
- `updatedAt`.

### JSON-представление

`ArchiveItem` сериализуется в JSON и целиком сохраняется в поле `data` SQLite. Это сознательно упрощает миграции и совместимость модели на этапе MVP.

---

## 8. SQLite

Реализация: `LocalArchiveRepository`.

Файл БД:

```text
product_boards.sqlite
```

Размещается в Android application documents directory.

### Текущая схема

В коде текущего репозитория:

```sql
CREATE TABLE archive_items (
  id TEXT PRIMARY KEY,
  data TEXT NOT NULL,
  normalized_url TEXT NOT NULL
);

CREATE INDEX idx_archive_items_normalized_url
ON archive_items(normalized_url);

CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  data TEXT NOT NULL
);
```

Версия схемы: **3**.

### Почему `data` хранится JSON

Плюсы текущего подхода:

- быстрый development;
- модель Dart остаётся источником структуры данных;
- миграция полей модели не требует большого количества SQL;
- легко хранить enum-значения.

Минусы:

- SQL не знает структуру карточки;
- сортировка/фильтрация по полям модели выполняется в Dart;
- большие коллекции будут масштабироваться хуже;
- изменение модели требует аккуратного `fromJson` compatibility logic.

### Производственный долг

Если архив вырастет до десятков тысяч объектов, рекомендуется перейти от JSON blob к нормализованным колонкам SQLite хотя бы для:

- title;
- categoryId;
- createdAt;
- updatedAt;
- metadataStatus;
- normalizedUrl.

---

## 9. Миграция legacy-данных

При обновлении с версии ниже текущей `LocalArchiveRepository`:

1. создаёт новые `archive_items` и `categories`;
2. ищет legacy-таблицы `boards` и `products`;
3. переносит доски в категории;
4. строит отображение `legacy board id -> category id`;
5. переносит товары в `ArchiveItem`;
6. переносит первый legacy board как `categoryId`;
7. сохраняет URL и изображение;
8. нормализует URL.

Миграция специально написана максимально терпимо к повреждённым legacy-строкам: отдельная битая запись пропускается, а не останавливает весь upgrade.

---

## 10. Жизненный цикл добавления ссылки

Основной pipeline:

```text
Android Share / Manual URL
          │
          ▼
      URL validation
          │
          ▼
   URL normalization
          │
          ▼
 Duplicate lookup in SQLite
          │
          ▼
   Create ArchiveItem
 metadataStatus = loading
 imageStatus    = loading
          │
          ▼
 repository.upsertItem()
          │
          ▼
 MetadataQueue.enqueue()
          │
          ▼
 ProductPreviewResolver
          │
          ├───────────────┐
          ▼               ▼
   ProductImporter   generic metadata
          │
          ▼
 HTTP / WebView / search fallback
          │
          ▼
 ImageCacheService
          │
          ▼
 repository.upsertItem()
```

Карточка создаётся **до** завершения сетевого импорта. Поэтому сетевой сбой не должен уничтожать пользовательское сохранение.

---

## 11. Android Share Intent

`AndroidManifest.xml` регистрирует `MainActivity` как обработчик:

- `ACTION_SEND + text/plain`;
- `ACTION_SEND + image/*`.

`MainActivity.kt` извлекает:

- URL из `EXTRA_TEXT` или `EXTRA_TITLE`;
- заголовок из `EXTRA_TITLE` или текста до URL;
- shared image, если Android передал URI изображения.

Shared image копируется во временный файл приложения.

### Cold start

Intent приходит до готовности Flutter engine:

```text
Intent
  ↓
pendingSharedData
  ↓
Flutter configure/init
  ↓
getInitialSharedData
  ↓
ArchiveScreen._consumeShare()
```

### Hot start

Если приложение уже запущено:

```text
onNewIntent()
  ↓
handleIncomingIntent()
  ↓
MethodChannel.sharedData
  ↓
Flutter handler
  ↓
ArchiveScreen._consumeShare()
```

Это разделение критично: без него Share Intent часто теряется при уже запущенном приложении.

---

## 12. Импорт метаданных

### 12.1 `ProductImporter`

`ProductImporter` — первый уровень marketplace-specific import.

Он пытается получить HTML через HTTP, затем для известных маркетплейсов при необходимости запускает native WebView.

Поддерживаемые специальные домены:

- Ozon;
- Wildberries;
- Avito;
- Яндекс Маркет;
- некоторые страницы Yandex.

### HTTP parser

Из HTML извлекаются:

1. `og:title`;
2. `twitter:title`;
3. marketplace-specific `h1`;
4. обычный `h1`;
5. `<title>`;
6. `product:price:amount`;
7. элементы с price-related selectors;
8. embedded `data-state` для цены;
9. JSON-LD `name`/`offers`;
10. fallback regex по embedded JSON.

HTTP timeout: около 12 секунд для marketplace importer.

---

## 13. Native WebView fallback

WebView реализован непосредственно в `MainActivity.kt`.

### Почему WebView нужен

Ozon/Wildberries и другие современные магазины часто:

- строят страницу JavaScript-ом;
- возвращают неполный HTML обычному HTTP-клиенту;
- требуют cookies;
- меняют DOM;
- используют антибот-защиту;
- не отдают прямой URL изображения.

Поэтому WebView является отдельным execution path.

### Настройки WebView

Включены:

- JavaScript;
- DOM storage;
- database storage;
- загрузка изображений;
- content/file access;
- cookies, включая third-party cookies;
- marketplace-compatible User-Agent.

WebView работает скрытым (`alpha = 0`) и используется как технический browser renderer.

### Timeout

Максимальное время browser resolve — около 20 секунд.

### Screenshot

После `onPageFinished` приложение ждёт дополнительное время и делает screenshot WebView.

Screenshot:

- создаётся как Bitmap;
- сохраняется JPEG;
- получает `file://` URI;
- затем копируется в постоянный локальный image cache.

Скриншот является **каноническим источником изображения для текущего marketplace WebView fallback**.

---

## 14. Ozon short-link pipeline

Короткие Ozon-ссылки являются отдельным сложным случаем.

Примерный pipeline:

```text
Ozon short URL
      │
      ▼
ProductImporter
      │
      ├── HTTP attempt
      │
      └── WebView attempt
              │
              ├── screenshot
              └── final URL/title/price
      │
      ▼
если screenshot не получен и есть shared title
      │
      ▼
MarketplaceSearchResolver
      │
      ▼
Google site:ozon.ru/product ...
      │
      ▼
candidate URLs
      │
      ▼
title similarity score
      │
      ▼
best candidate >= threshold
      │
      ▼
WebView candidate
      │
      ▼
screenshot + title + price
```

### Поиск кандидата

Текущая реализация использует несколько поисковых стратегий:

- exact Google query;
- relaxed Google query;
- brand-oriented query;
- generic Ozon query.

Результаты дедуплицируются и ранжируются по token-based F1 similarity.

Порог выбора кандидата:

```text
score >= 0.45
```

Это эвристика, а не гарантия точного соответствия товара.

---

## 15. Выбор title

Title проходит несколько источников.

Приоритет определяется не только порядком источников, но и quality score.

Учитывается:

- длина;
- наличие кириллицы;
- наличие потенциально мусорного латинского значения.

Кириллический title получает большой бонус, поэтому это одновременно механизм защиты от известной проблемы Share Intent, когда маркетплейс передаёт техническую/латинскую строку вместо нормального русского названия.

Если ничего не найдено, используется fallback из URL path.

---

## 16. `ProductPreviewResolver`

Это верхний orchestration layer импорта.

Он объединяет:

```text
ProductImporter
        │
        ├── imported title
        ├── screenshot
        ├── price
        └── resolved URL

MarketplaceSearchResolver
        │
        └── candidate Ozon URL

ImageCacheService
        │
        └── persistent local image
```

Результат представлен `ProductPreview`.

Для текущей реализации поле `imageUrl` намеренно может оставаться `null`, если изображение получено как локальный screenshot. В таком случае используется `localImageUri`.

---

## 17. Image cache

Файл: `lib/services/image_cache_service.dart`.

Каталог:

```text
<application documents>/pinzon_images/
```

### Remote image

При получении URL:

1. URL парсится;
2. выполняется HTTP GET;
3. передаётся User-Agent;
4. при необходимости передаётся Referer;
5. проверяется HTTP status;
6. проверяется MIME/magic bytes;
7. слишком маленькие payload отбрасываются;
8. вычисляется SHA-1 URL;
9. файл сохраняется локально.

Минимальный размер изображения: **4096 bytes**.

### Local screenshot

Для `file://` URI:

1. проверяется существование файла;
2. читаются bytes;
3. проверяется формат;
4. вычисляется SHA-1 содержимого;
5. файл копируется в `pinzon_images`.

### Почему кэш важен

После первоначального импорта UI больше не зависит от доступности исходного CDN изображения. Это особенно важно для Ozon/WB, где remote image URL может быть временным или требовать специальные headers.

---

## 18. Generic metadata fallback

`MetadataService` является вторым/общим уровнем metadata extraction.

Если специализированный `ProductPreviewResolver` не дал полный результат, выполняется обычный HTTP GET страницы.

Извлекаются:

- `og:title`;
- `twitter:title`;
- `<title>`;
- `og:image`;
- `twitter:image`;
- `[itemprop="image"]`;
- JSON-LD `name`;
- JSON-LD `image`.

Если image — remote URL, он дополнительно отправляется в `ImageCacheService`.

---

## 19. Metadata Queue

`MetadataQueue` отделяет сохранение карточки от сетевого импорта.

### Состояния

До обработки:

```text
metadataStatus = loading
imageStatus    = loading
```

После успеха:

```text
success / success
```

Если найден только title или только image:

```text
partial
```

Если импорт полностью не удался:

```text
failed / failed
```

### Retry policy

Используются четыре попытки с задержками:

```text
0 s
2 s
5 s
10 s
```

Повторная обработка защищена map `_running`, чтобы один item не обрабатывался параллельно несколькими задачами.

### Recovery после перезапуска

При старте приложения `resumePending()` ищет карточки с:

```text
metadataStatus == loading
```

и ставит их снова в очередь.

---

## 20. URL normalization

`UrlNormalizer` используется для поиска потенциальных дубликатов.

Нормализованное значение хранится отдельно от исходного URL:

```text
ArchiveItem.url
      │
      ▼
UrlNormalizer.normalize()
      │
      ▼
archive_items.normalized_url
```

Это позволяет сохранить оригинальную ссылку пользователя и одновременно сравнивать ссылки в устойчивой форме.

Важно: проверка дубликатов **не запрещает сохранение**. Пользователю показывается подтверждение, после которого можно создать независимый объект.

---

## 21. Диагностика

В проекте есть `ImageDiagnostics` и отдельный `ImageDiagnosticsScreen`.

Диагностика используется для восстановления причин проблем с картинками и импортом.

Типичные стадии:

```text
SHARE_INPUT
IMPORT_HTTP
WEBVIEW_START
WEBVIEW_EVENT
WEBVIEW_RESULT
SCREENSHOT_START
SCREENSHOT_SOURCE_SELECTED
SCREENSHOT_CACHE_RESULT
SEARCH_START
SEARCH_CANDIDATES
SEARCH_SELECTED
PREVIEW_RESULT
```

Ошибки логируются с этапом, URL и, где возможно, stack trace.

### Практический принцип

При проблеме «название есть, картинки нет» сначала нужно определить, на каком этапе исчезло изображение:

```text
HTTP image
    ↓
WebView screenshot
    ↓
local cache
    ↓
ArchiveItem.imageUrl
    ↓
ProductPreviewImage
```

Не следует сразу менять parser, если проблема находится на этапе cache/UI.

---

## 22. UI image rendering

`ProductPreviewImage` должен учитывать как минимум два типа источников:

- remote URL;
- local `file://` URI.

Для текущего marketplace pipeline предпочтителен локальный URI, потому что screenshot уже сохранён в application storage.

---

## 23. Android build configuration

Файл: `android/app/build.gradle.kts`.

Основные параметры:

```text
namespace      = com.example.productboards
applicationId  = com.example.productboards
minSdk         = 24
compileSdk     = flutter.compileSdkVersion
targetSdk      = flutter.targetSdkVersion
Java           = 17
Kotlin JVM     = 17
```

Release:

- `minifyEnabled = true`;
- `shrinkResources = true`;
- ProGuard/R8 используется;
- signing подключается только при наличии `key.properties`.

Debug получает:

```text
applicationIdSuffix = .debug
```

---

## 24. Android permissions

Текущий manifest требует:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Отдельного storage permission для современных Android не требуется, потому что приложение использует собственное private application storage.

---

## 25. CI/CD

Workflow:

```text
.github/workflows/build-android.yml
```

Триггеры:

- `workflow_dispatch`;
- `pull_request`;
- push в `main`;
- push в `master`;
- push в `fix/android-gradle-compat`.

### Pipeline

```text
Checkout
  ↓
Detect Flutter project root
  ↓
Flutter 3.38.1
  ↓
flutter pub get
  ↓
flutter analyze
  ↓
flutter test
  ↓
Gradle 8.13
  ↓
Regenerate Gradle Wrapper
  ↓
Configure release signing
  ↓
flutter build apk --release
  ↓
flutter build apk --split-per-abi
  ↓
flutter build appbundle --release
  ↓
Upload artifacts
```

### Signing

Если существуют GitHub secrets:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

используется постоянный keystore.

Если secrets отсутствуют, CI создаёт временный keystore. Такой APK устанавливается, но AAB нельзя использовать для стабильной публикации/обновлений в Google Play.

---

## 26. Тесты

Сейчас присутствуют минимум следующие тестовые наборы:

```text
test/archive_item_test.dart
test/product_importer_test.dart
test/url_normalizer_test.dart
```

### Что покрывается

- сериализация/десериализация `ArchiveItem`;
- импорт HTML metadata и цены;
- URL normalization.

### Что пока недостаточно покрыто

Наиболее критичные участки для расширения тестами:

1. `MetadataQueue` retry/recovery;
2. `ProductPreviewResolver` orchestration;
3. Ozon short-link search scoring;
4. WebView bridge contract;
5. SQLite migration v2/v3;
6. category CRUD;
7. duplicate flow;
8. local image cache;
9. Share Intent cold/hot start.

---

## 27. Контракт native bridge

Flutter вызывает:

```text
MethodChannel('product_boards/share')
```

### `getInitialSharedData`

Ответ — map примерно такого вида:

```json
{
  "url": "https://...",
  "title": "...",
  "imagePath": "file:///..."
}
```

### `sharedData`

Тот же payload приходит push-событием при `onNewIntent`.

### `resolveProduct`

Flutter передаёт:

```json
{
  "url": "https://..."
}
```

Native side возвращает map с потенциальными полями:

```json
{
  "originalUrl": "...",
  "finalUrl": "...",
  "pageTitle": "...",
  "title": "...",
  "price": 1234.0,
  "currency": "RUB",
  "description": "...",
  "screenshotUri": "file:///...",
  "reason": "success",
  "attempts": 1,
  "diagnostics": []
}
```

Контракт намеренно допускает отсутствующие поля.

---

## 28. Основные технические риски

### 28.1. Marketplace anti-bot

Самая высокая неопределённость проекта. Код работает непосредственно против внешних сайтов, структура которых может измениться без предупреждения.

### 28.2. WebView screenshot

Screenshot зависит от:

- размера WebView;
- времени загрузки;
- JS rendering;
- cookies;
- redirect chain;
- антибот-страницы;
- device WebView implementation.

### 28.3. Search fallback

Поиск Ozon по title является эвристикой. Теоретически возможен выбор похожего, но другого товара.

### 28.4. JSON blob SQLite

При большом объёме данных будут расти стоимость чтения и фильтрации.

### 28.5. Большой `main.dart`

UI, navigation, import orchestration и category management частично находятся в одном файле. Это повышает стоимость изменений и вероятность регрессий.

### 28.6. Отсутствие backend

Это плюс для приватности и простоты, но означает отсутствие:

- server-side proxy;
- нормального marketplace API adapter;
- фонового обновления вне приложения;
- облачной синхронизации.

---

## 29. Рекомендуемая следующая архитектурная итерация

### Этап 1 — стабилизация текущего MVP

1. Вынести Share Intent в `ShareIntentService`.
2. Вынести browser bridge в `AndroidProductResolver`.
3. Вынести UI orchestration из `main.dart`.
4. Ввести единый `ImportResult` с источником данных и confidence.
5. Добавить integration tests для import pipeline.
6. Добавить миграционные тесты SQLite.

### Этап 2 — унификация marketplace adapters

Вместо большого conditional pipeline:

```text
ProductImporter
```

перейти к:

```text
MarketplaceResolver
├── OzonResolver
├── WildberriesResolver
├── YandexMarketResolver
├── AvitoResolver
└── GenericWebResolver
```

Каждый adapter должен иметь единый контракт:

```text
resolve(URL) -> ProductImportResult
```

### Этап 3 — confidence-based import

Каждый источник должен возвращать не только значение, но и уверенность:

```text
title
  value
  source
  confidence

image
  value
  source
  confidence

price
  value
  source
  confidence
```

Это позволит безопаснее выбирать между:

- Share title;
- HTML title;
- JSON-LD;
- WebView title;
- search candidate.

### Этап 4 — локальная AI-сортировка

После стабилизации модели `ArchiveItem` локальная AI должна работать поверх уже сохранённых данных и не участвовать в первичном импорте.

Рекомендуемый pipeline:

```text
ArchiveItem
   ↓
feature extraction
   ↓
local embedding / classifier
   ↓
category recommendation
   ↓
user confirmation
   ↓
ArchiveItem.categoryId
```

Это позволит внедрить AI без зависимости от marketplace scraping.

---

## 30. Инварианты, которые нельзя ломать

При дальнейшей разработке необходимо сохранять следующие правила.

### Данные

- Сохранение ссылки не должно зависеть от успешного network import.
- `ArchiveItem.url` должен сохраняться в исходном пригодном для открытия виде.
- `normalized_url` используется для поиска дубликатов, но не заменяет исходный URL.
- Удаление категории должно переводить её элементы в `categoryId = null`.
- `titleSource = manual` означает, что автоматический importer не должен перезаписывать ручной title.

### Изображения

- Remote image нельзя считать надёжно доступным только потому, что URL получен.
- Local screenshot/image должен кэшироваться перед долгосрочным использованием.
- Нельзя сохранять HTML/anti-bot страницу как будто это изображение.

### Импорт

- Ошибка WebView не должна удалять уже созданную карточку.
- Ошибка search fallback не должна останавливать generic import.
- Retry не должен запускать несколько параллельных job для одного item.

### Android

- Нельзя удалять cold-start Share Intent handling.
- Нельзя менять MethodChannel contract без синхронного изменения Dart и Kotlin.
- `resolveProduct` должен возвращать nullable-safe payload.

---

## 31. Практический порядок диагностики проблем

### Проблема: ссылка не добавляется

Проверить:

1. URL scheme — только `http/https`;
2. Share Intent payload;
3. `getInitialSharedData` / `sharedData`;
4. duplicate dialog;
5. SQLite `upsertItem`.

### Проблема: название неправильное

Проверить:

1. shared title;
2. HTTP title;
3. WebView title;
4. `ImportedProductData._selectTitle`;
5. `ProductPreviewResolver._chooseTitle`;
6. ручной `titleSource`.

### Проблема: Ozon не даёт изображение

Проверить в таком порядке:

```text
Share URL
  ↓
HTTP import
  ↓
WebView start
  ↓
PAGE_FINISHED
  ↓
SCREENSHOT_START
  ↓
SCREENSHOT_ALLOWED
  ↓
SCREENSHOT_RESULT
  ↓
cacheLocalUri
  ↓
ArchiveItem.imageUrl
```

Если short link:

```text
OZON_SEARCH_FALLBACK_START
  ↓
SEARCH_START
  ↓
SEARCH_CANDIDATES
  ↓
SEARCH_SELECTED
  ↓
candidate WebView
```

### Проблема: APK не устанавливается

Проверить:

1. `applicationId`;
2. подпись APK;
3. конфликт установленной версии с другим signing key;
4. целевую архитектуру APK;
5. результат CI artifact;
6. release minification/R8.

---

## 32. Безопасность и приватность

Текущая архитектура не требует аккаунта и собственного backend.

URL товаров и локальные карточки не отправляются на сервер Pinzon, потому что такого backend в приложении нет.

Однако важно понимать, что **импорт внешних страниц сам по себе создаёт сетевые запросы к сторонним сервисам**:

- marketplace URL;
- поисковая система при Ozon search fallback;
- CDN изображений.

Поэтому «без backend» не означает «без сетевого трафика».

### Что не должно попадать в Git

Нельзя коммитить:

```text
android/key.properties
*.jks
*.keystore
release credentials
GitHub secrets
```

---

## 33. Build checklist

Перед релизной сборкой:

```text
[ ] flutter pub get
[ ] flutter analyze
[ ] flutter test
[ ] flutter build apk --release
[ ] flutter build appbundle --release
[ ] проверить applicationId
[ ] проверить release signing
[ ] проверить Share Intent
[ ] проверить Ozon short URL
[ ] проверить обычный Ozon URL
[ ] проверить Wildberries
[ ] проверить Яндекс Маркет
[ ] проверить ручное добавление URL
[ ] проверить duplicate flow
[ ] проверить создание/удаление категории
[ ] проверить отсутствие потери карточки при metadata failure
```

---

## 34. Краткая карта ответственности файлов

| Файл | Ответственность |
|---|---|
| `lib/main.dart` | bootstrap приложения и основной UI flow |
| `models/archive_item.dart` | модель карточки |
| `models/category.dart` | модель подборки |
| `models/product_preview.dart` | временный результат импорта |
| `repositories/archive_repository.dart` | storage abstraction |
| `repositories/local_archive_repository.dart` | SQLite implementation |
| `services/url_normalizer.dart` | нормализация URL |
| `services/metadata_queue.dart` | retry/background import queue |
| `services/metadata_service.dart` | generic metadata extraction |
| `services/product_importer.dart` | marketplace import + WebView bridge |
| `services/product_preview_resolver.dart` | import orchestration |
| `services/marketplace_search_resolver.dart` | Ozon search fallback |
| `services/image_cache_service.dart` | persistent image cache |
| `services/image_diagnostics.dart` | structured import diagnostics |
| `screens/image_diagnostics_screen.dart` | просмотр диагностики |
| `widgets/product_preview_image.dart` | rendering image source |
| `android/.../MainActivity.kt` | Share Intent + WebView |
| `android/.../AndroidManifest.xml` | Android components/intent filters |
| `android/app/build.gradle.kts` | Android build/signing |
| `.github/workflows/build-android.yml` | CI build/test/artifacts |

---

## 35. Источник истины

При дальнейшей разработке использовать следующий порядок приоритетов:

1. текущий исходный код;
2. тесты;
3. CI workflow;
4. эта техническая документация;
5. `README.md` как пользовательский/исторический обзор.

Если реализация меняется, этот документ необходимо обновлять вместе с архитектурным изменением.

---

## 36. Зафиксированное состояние на 20.08.2026

Последний просмотренный commit `main`:

```text
1b3c8043132c00977b5ddb37163a553d46f96e47
fix: restore working Pinzon runtime flow
```

Непосредственно перед ним в истории присутствуют исправления SQLite queries и Android WebView/Kotlin payload flow.

Эта фиксация важна для понимания контекста: текущая архитектура уже содержит несколько последовательных repair-итераций вокруг Android WebView, Share Intent, SQLite и marketplace image import. Поэтому дальнейшие изменения желательно делать небольшими изолированными слоями, сохраняя существующий диагностический pipeline.

---

## 37. Главный архитектурный вывод

Pinzon уже фактически разделён на три независимые подсистемы:

```text
1. LOCAL ARCHIVE
   SQLite + models + categories

2. IMPORT ENGINE
   HTTP + HTML + JSON-LD + WebView + Ozon search

3. ANDROID BRIDGE
   Share Intent + WebView + screenshot
```

Главная задача следующей стадии — не добавлять ещё больше логики в `main.dart` и `ProductImporter`, а формализовать эти границы.

Целевая форма после рефакторинга:

```text
UI
 │
 ▼
ArchiveController
 │
 ├── ArchiveRepository
 │
 └── ImportCoordinator
       │
       ├── MarketplaceResolver
       │     ├── Ozon
       │     ├── Wildberries
       │     ├── Yandex
       │     └── Generic
       │
       ├── AndroidBrowserBridge
       └── ImageCache
```

Такой переход даст наиболее безопасную основу для дальнейших функций Pinzon, включая локальную AI-сортировку, не связывая AI с нестабильным scraping-кодом маркетплейсов.
