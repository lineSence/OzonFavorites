# Pinzon LLM Analysis Bundle

This documentation is intended to accompany an exported repository snapshot when the project is analyzed by another LLM.

## Recommended analysis order

1. Read this file and `LLM_ANALYSIS_CONTEXT.md`.
2. Read the repository `README.md` and `pubspec.yaml`.
3. Inspect `lib/main.dart` to understand application composition.
4. Trace the import path from Android Share → `MainActivity.kt` → Flutter import service → metadata/preview resolution → local repository → UI.
5. Inspect image caching/diagnostics and the image widget separately.
6. Read all tests and compare their coverage with the failure history in `LLM_ANALYSIS_CONTEXT.md`.
7. Inspect CI and Android Gradle configuration.
8. Use Git history to understand why unusual compatibility workarounds exist before proposing removals.

## Repository snapshot notes

The repository may contain a nested Flutter project under `product_boards/`. Do not assume the repository root is the Flutter project root. The CI workflow explicitly detects `pubspec.yaml` for this reason.

## What not to infer

- Do not assume marketplace scraping is stable merely because a resolver exists.
- Do not assume an image URL is valid because metadata contains one; image diagnostics and cache behavior matter.
- Do not assume a release APK is Play Store-ready when CI falls back to a throwaway keystore.
- Do not remove compatibility code without checking the Git history and recent build failures.

## Desired output of a deep LLM review

A high-quality analysis should identify:

- architecture and dependency boundaries;
- concrete correctness bugs and their root causes;
- production reliability risks;
- performance and memory risks;
- Android-specific risks;
- marketplace integration fragility;
- security/privacy issues;
- test gaps;
- CI/release weaknesses;
- prioritized remediation plan with minimal-risk sequencing;
- opportunities to simplify the code without losing behavior.
