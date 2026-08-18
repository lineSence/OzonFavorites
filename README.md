# Product Boards 1.0

Offline-first менеджер закладок товаров в стиле Pinterest. Приложение принимает URL через Android Share, пытается получить Open Graph/JSON-LD данные страницы, а затем предлагает сохранить товар в одну или несколько досок.

## Что готово

- Android Share: OZON → «Поделиться» → Product Boards.
- Корректная обработка cold start и hot start при получении Share Intent.
- Автоматический импорт title/image/price по HTML metadata.
- Fallback: если магазин не отдал метаданные, товар всё равно сохраняется и редактируется вручную.
- SQLite вместо SharedPreferences для постоянных данных.
- Автоматическая миграция данных старого MVP.
- Pinterest-like masonry и список.
- Доски, теги, заметки, приоритет и статусы.
- Поиск и сортировка.
- Проверка дубликатов ссылок.
- Отслеживание цен: обновление при открытии приложения и по кнопке, история цен с графиком, индикатор «цена снизилась».
- Открытие исходного товара.
- JSON-резервная копия через системное меню Share и восстановление из буфера обмена.
- Никаких облачных сервисов, аккаунтов или Firebase/Supabase.
- Иконка приложения (adaptive icon + PNG для старых Android).
- Линтинг через `flutter_lints` (`analysis_options.yaml`) и unit/widget-тесты.

## Требования

Flutter 3.38.1+ / Dart 3.10+. Android SDK и Java 17.

Для актуальных зависимостей проекта используются версии, требующие современный Android Gradle Plugin. `share_plus 13.3.x` требует Android Gradle Plugin 8.12.1+, Gradle 8.13+, Kotlin 2.2.0 и Java 17.

## Сборка

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Для Google Play:

```bash
flutter build appbundle --release
```

### Подпись release

По умолчанию release собирается без приватного signing key. Для подписанного релиза скопируйте `android/key.properties.example` в `android/key.properties`, укажите путь к `.jks`, а затем выполните обычную release-сборку. `android/key.properties` и ключи уже добавлены в `.gitignore`.

CI (`build-android.yml`) подписывает сборку автоматически:

- Если в репозитории заданы секреты `ANDROID_KEYSTORE_BASE64` (base64 от `.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` — используется постоянный ключ; такой AAB можно публиковать в Google Play и обновлять приложение поверх предыдущих артефактов.
- Без секретов CI генерирует одноразовый keystore: APK устанавливаются на устройство, но AAB не подходит для Play и обновлений (ключ меняется при каждой сборке).

`applicationId` сейчас `com.example.productboards`; перед публикацией замените его на собственный уникальный идентификатор.

### Иконка приложения

Иконка лежит в `android/app/src/main/res`:

- `mipmap-anydpi-v26/ic_launcher.xml` — adaptive icon (API 26+);
- `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` — запасные PNG (API 24–25).

Для перегенерации PNG-иконок запустите `scripts/generate_launcher_icons.ps1` (Windows) — скрипт рисует минималистичную закладку на фоне `#F6F6F4`.

## Важный нюанс OZON

Импорт выполняется непосредственно на устройстве по URL, без собственного сервера. Это сохраняет приватность и позволяет работать без аккаунта, но HTML-карточка магазина может быть недоступна для автоматического чтения из-за изменений страницы, редиректов или антибот-защиты. Поэтому UI всегда допускает ручное заполнение карточки.

## Где хранятся данные

SQLite-файл (схема **v2**) находится в private application documents directory Android. Схема v2 добавляет:

- таблицы `tags` (вложенные теги с `parentId`) и `product_tags` (связь товар-тег);
- таблицу `price_history` (история цен по товарам);
- новые поля товара: `quantity`, `comparisonUrl`, `desiredPurchaseDate`, `lastCheckedAt`, `priceLowest`.

При обновлении с v1 миграция автоматически переносит плоские теги (строки) в сущность `Tag` и связывает их с товарами. Из приложения данные не уходят на сервер Product Boards.

> В текущем контейнере Flutter SDK не установлен, поэтому фактический `flutter pub get/analyze/test/build` здесь не запускался. Если архив развернут в окружении, где отсутствует `android/gradle/wrapper/gradle-wrapper.jar`, один раз запустите `scripts/bootstrap_gradle_wrapper.ps1` (Windows) или `scripts/bootstrap_gradle_wrapper.sh` (Linux/macOS); скрипт берёт стандартные wrapper-файлы из установленного Flutter SDK и не перезаписывает код приложения.
