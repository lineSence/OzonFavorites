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
- Открытие исходного товара.
- JSON-резервная копия через системное меню Share и восстановление из буфера обмена.
- Никаких облачных сервисов, аккаунтов или Firebase/Supabase.

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

`applicationId` сейчас `com.example.productboards`; перед публикацией замените его на собственный уникальный идентификатор.

## Важный нюанс OZON

Импорт выполняется непосредственно на устройстве по URL, без собственного сервера. Это сохраняет приватность и позволяет работать без аккаунта, но HTML-карточка магазина может быть недоступна для автоматического чтения из-за изменений страницы, редиректов или антибот-защиты. Поэтому UI всегда допускает ручное заполнение карточки.

## Где хранятся данные

SQLite-файл находится в private application documents directory Android/iOS. Из приложения данные не уходят на сервер Product Boards.

> В текущем контейнере Flutter SDK не установлен, поэтому фактический `flutter pub get/analyze/test/build` здесь не запускался. Если архив развернут в окружении, где отсутствует `android/gradle/wrapper/gradle-wrapper.jar`, один раз запустите `scripts/bootstrap_gradle_wrapper.ps1` (Windows) или `scripts/bootstrap_gradle_wrapper.sh` (Linux/macOS); скрипт берёт стандартные wrapper-файлы из установленного Flutter SDK и не перезаписывает код приложения.
