# Сборка APK через GitHub Actions

Этот проект можно собирать в облаке без установленного Flutter SDK на компьютере.

## 1. Создать репозиторий

На GitHub создай новый репозиторий и загрузи **содержимое** этой папки.
Файл `pubspec.yaml` должен находиться в корне репозитория.

## 2. Запустить сборку

Открой:

`Actions → Build Android → Run workflow`

После окончания job открой страницу запуска workflow и скачай artifact:

- `product-boards-apk` — универсальный APK;
- `product-boards-split-apks` — APK по архитектурам;
- `product-boards-aab` — Android App Bundle для публикации.

## 3. Установка APK

Для обычного личного тестирования используй `product-boards-apk`.

Если GitHub собрал APK без release-подписи, Android может не разрешить установить его как обычное приложение. Для постоянного использования и обновлений рекомендуется настроить signing workflow ниже.

## 4. Постоянная release-подпись

Для workflow `Build signed Android release` добавь в GitHub repository secrets:

- `ANDROID_KEYSTORE_BASE64` — содержимое keystore в base64;
- `ANDROID_STORE_PASSWORD` — пароль хранилища;
- `ANDROID_KEY_ALIAS` — alias ключа;
- `ANDROID_KEY_PASSWORD` — пароль ключа.

После этого:

`Actions → Build signed Android release → Run workflow`

Скачай:

- `product-boards-signed-apk` — подписанный APK;
- `product-boards-signed-aab` — подписанный AAB.

**Не загружай keystore и пароли в репозиторий.**

## 5. Важно для обновлений

Используй один и тот же release keystore для всех будущих версий приложения. Иначе Android не позволит установить новую версию поверх старой.

## 6. Что делает обычный workflow

При push в `main`/`master` или при ручном запуске он:

1. устанавливает Flutter 3.38.1 в GitHub Actions;
2. загружает зависимости;
3. запускает `flutter analyze`;
4. запускает тесты;
5. собирает универсальный APK;
6. собирает APK по ABI;
7. собирает AAB;
8. публикует результаты как workflow artifacts.
