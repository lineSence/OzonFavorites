# Pinzon architecture

## Purpose

Pinzon is a local-first visual archive of links. A saved link is an `ArchiveItem`; collections are `Category` objects. Metadata enrichment is asynchronous and must never block persistence of the original URL.

## Dependency direction

```text
main.dart
  -> app/
  -> screens/
  -> widgets/
  -> repositories/
  -> services/
  -> models/
```

Rules:

- `models/` contains domain data only.
- `repositories/` owns persistence and migration. Screens never access SQLite directly.
- `services/` performs metadata import, image caching, screenshot cleanup, URL normalization and classification.
- `widgets/` are reusable presentation components and should not contain persistence logic.
- `screens/` coordinate user flows; large algorithms belong in services.
- `app/` owns Android share bridge and application-level composition.
- `main.dart` must remain bootstrap-only.

## Metadata pipeline

```text
Share / manual URL
       |
       v
ArchiveRepository.upsertItem()
       |
       v
MetadataQueue
       |
       v
MetadataService
       |
       +--> ProductPreviewResolver
       |       +--> ProductImporter
       |       +--> Android WebView bridge
       |       +--> MarketplaceSearchResolver (Ozon fallback)
       |
       +--> generic HTML metadata fallback
       |
       v
ImageCacheService
       |
       v
SmartCropService
       |
       v
ArchiveRepository.update
```

The archive remains usable when metadata fails. Manual titles must never be overwritten by automatic enrichment.

## AI editing rules

1. Search for the owning layer before editing a file.
2. Do not put new business logic in `main.dart`.
3. Do not access SQLite from UI.
4. Do not duplicate image loading; use `ArchiveImage` / `ImageCacheService`.
5. Keep external marketplace logic behind services.
6. Preserve `ArchiveItem` as the canonical persisted object.
7. New classifier/AI logic belongs in a service with a small deterministic API.
8. Add or update unit tests for deterministic services.
9. Prefer small files with one responsibility.
10. Do not log raw user URLs unless diagnostics explicitly require them.

## Current experimental capabilities

The production refactor incorporates the experimental local pipeline where it is compatible with the archive architecture:

- deterministic Smart Sort classifier;
- classifier-friendly `ProductFeatures`;
- marketplace search fallback for Ozon;
- WebView product preview/import;
- local image cache with validation;
- structured image diagnostics;
- conservative screenshot smart crop;
- URL normalization and duplicate detection;
- tests for Smart Sort and archive model behavior.

## Future boundaries

The next architectural steps are:

- extract archive screen state/actions into a controller or view-model;
- introduce explicit `MetadataResolver` interfaces and provider implementations;
- add repository integration tests including migration from legacy `products/boards`;
- add import/metadata fixture tests without network access;
- add an application-wide result/error model;
- make Smart Sort suggestions reviewable before automatic category assignment;
- remove remaining legacy product terminology once migration coverage is complete.
