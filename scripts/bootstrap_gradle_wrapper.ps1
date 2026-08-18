# Generates the standard Gradle wrapper binaries from the installed Flutter SDK.
# Run from the repository root when android/gradle/wrapper/gradle-wrapper.jar is missing.
$ErrorActionPreference = 'Stop'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter is not on PATH.'
}
$temp = Join-Path $env:TEMP ('product_boards_wrapper_' + [guid]::NewGuid())
try {
  flutter create --platforms=android --project-name=wrapper_seed $temp | Out-Host
  Copy-Item "$temp/android/gradlew" "android/gradlew" -Force
  Copy-Item "$temp/android/gradlew.bat" "android/gradlew.bat" -Force
  Copy-Item "$temp/android/gradle/wrapper/gradle-wrapper.jar" "android/gradle/wrapper/gradle-wrapper.jar" -Force
  Write-Host 'Gradle wrapper installed.'
} finally {
  if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
}
