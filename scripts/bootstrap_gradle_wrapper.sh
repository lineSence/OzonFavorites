#!/usr/bin/env bash
set -euo pipefail
command -v flutter >/dev/null || { echo 'Flutter is not on PATH.' >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
flutter create --platforms=android --project-name=wrapper_seed "$tmp" >/dev/null
cp "$tmp/android/gradlew" android/gradlew
cp "$tmp/android/gradlew.bat" android/gradlew.bat
cp "$tmp/android/gradle/wrapper/gradle-wrapper.jar" android/gradle/wrapper/gradle-wrapper.jar
chmod +x android/gradlew
echo 'Gradle wrapper installed.'
