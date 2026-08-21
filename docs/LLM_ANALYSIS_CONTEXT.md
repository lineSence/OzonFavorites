# Pinzon — LLM Analysis Context

## Purpose

This file is an orientation layer for an LLM performing a deep technical/product analysis of the repository. The authoritative implementation is the code in `product_boards/`; Git history is included separately in the analysis bundle.

## Product identity

- Current product name: **Pinzon**.
- Repository name: `OzonFavorites`.
- The original project/package directory is `product_boards`.
- Target platform: Android.
- Framework: Flutter.
- Flutter version used by CI: 3.38.1.
- The product concept evolved from an Ozon-focused favorites/bookmark app into a visual archive of links/products with Pinterest-like cards and local-first processing.

## Core product idea

The app receives product/link data, especially through Android Share, stores it locally, enriches it with metadata/images/prices when possible, and presents the result as visual cards that can later be organized. A key design constraint is avoiding mandatory cloud/backend functions for the MVP.

## Current architecture visible in repository

- `lib/main.dart` — main application/UI orchestration.
- `lib/models/` — archive and preview data models.
- `lib/repositories/` — persistence abstraction and local archive repository.
- `lib/services/product_importer.dart` — import pipeline.
- `lib/services/product_preview_resolver.dart` — preview resolution.
- `lib/services/marketplace_search_resolver.dart` — marketplace discovery/resolution.
- `lib/services/metadata_service.dart` and `metadata_queue.dart` — metadata enrichment and asynchronous work.
- `lib/services/image_cache_service.dart` and `image_diagnostics.dart` — image caching/diagnostics.
- `lib/services/url_normalizer.dart` — URL normalization.
- `lib/widgets/product_preview_image.dart` — image rendering widget.
- `lib/screens/image_diagnostics_screen.dart` — diagnostics UI.
- `android/app/src/main/kotlin/com/example/productboards/MainActivity.kt` — Android platform/share integration.
- `.github/workflows/build-android.yml` — CI build/test/package pipeline.

## Known development history / issues

1. Early builds had project-root detection and Flutter workspace issues (`Expected to find project root in current working directory`).
2. CI dependency resolution previously failed because `flutter_lints` could not be resolved due to pub.dev authorization/permission problems.
3. Gradle wrapper/build problems occurred, including a broken/missing `gradle-wrapper.jar` and `no main manifest attribute` errors. CI was subsequently designed to regenerate the Gradle wrapper.
4. GitHub Actions YAML syntax errors occurred during iteration.
5. APK installation previously failed with a package invalid/corrupted error; signing/build configuration was subsequently revised.
6. Android Share import from Ozon initially produced garbled Latin-character titles and failed to obtain images.
7. Marketplace extraction has been unreliable: Yandex Market data worked in one iteration while Ozon and Wildberries did not.
8. Image rendering previously produced blank/white cards. A later version fixed the blank-image problem.
9. A more recent UI bug: after an image is loaded it briefly flashes at full-screen size before settling into the card; card images are also cropped square. The intended UX change is to allow opening/expanding the image from the card rather than forcing a permanently square presentation.
10. An image diagnostics JSON/log format was introduced to investigate image failures.
11. The project has been repeatedly optimized toward a production-ready Android build without relying on cloud functions.

## Important current technical signals

- CI currently regenerates the Gradle wrapper during builds instead of trusting the checked-in wrapper JAR.
- CI uses Flutter 3.38.1 and Gradle 8.13.
- Release signing supports a permanent keystore through GitHub secrets; otherwise CI creates a throwaway installable signing key.
- CI runs `flutter pub get`, `flutter analyze`, `flutter test`, APK builds, split APK builds, and AAB build.
- Existing tests cover archive items, product importing, and URL normalization.

## Analysis priorities

For a deep review, inspect these areas first:

1. Import correctness and resilience for Android Share intents.
2. Marketplace URL normalization and extraction strategy, including Ozon/Wildberries/Yandex fallbacks.
3. Metadata/image resolution reliability, timeout/error handling, caching, retries, and concurrency.
4. Image lifecycle and UI layout: transient full-size rendering, aspect-ratio/cropping, cache transitions, and expandable image UX.
5. Local persistence integrity, migrations/versioning, duplicate detection, and recovery from malformed records.
6. Separation of UI, domain logic, repositories, and external/network concerns.
7. Production performance, memory use, network behavior, offline behavior, and battery impact.
8. Android share-target behavior across Android versions and OEMs.
9. CI reproducibility, release signing, artifact integrity, and dependency supply-chain risks.
10. Test coverage around the actual failure modes observed during development.

## Security / privacy expectations

Do not assume credentials, keystores, or runtime secrets belong in the archive. Preserve example configuration only. Treat the repository as potentially containing implementation details that should be reviewed for accidental secrets before external sharing.

## Bundle semantics

The companion LLM bundle should contain:

- the complete current repository snapshot;
- Git history sufficient to reconstruct development evolution;
- project documentation and this context file;
- CI configuration;
- tests and scripts;
- a manifest describing the snapshot commit and bundle contents.

The Git history is the source of truth for chronology; this document intentionally summarizes only the known product/development context and should not override code or commits.
