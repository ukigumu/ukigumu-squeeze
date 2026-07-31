# Grumpy Squeeze

Grumpy Squeeze is a native macOS image compressor and converter by **Grumpy Software**.
It processes files locally, includes no telemetry, accounts, analytics, uploads, or
network requests, and requires macOS 14 or later.

## Current MVP

- Drop files and folders, or select them with the native file panel.
- Recursive content-based discovery without following symbolic links.
- JPEG/JPG, PNG, AVIF, HEIC, TIFF, and WebP input.
- JPEG, PNG, AVIF, HEIC, and TIFF output through ImageIO when available at runtime.
- WebP output through the bundled, local libwebp 1.5.0 encoder.
- Concurrent, cancellable processing with bounded structured concurrency.
- Optional destination that leaves sources untouched.
- Recoverable in-place writes through a lowercase `original` tree.
- Temporary-file encoding, reopen/format/dimension validation, and rollback.
- Exact `.jpg`/`.jpeg` preservation when the format is unchanged.
- Collision detection before processing.
- Embedded metadata preservation/removal independent of JSON export.
- Deterministic, atomic `grumpy-squeeze-metadata.json` reports without absolute paths.
- App Sandbox with user-selected read/write access.
- Stable accessibility identifiers on primary controls.

Open `GrumpySqueeze.xcodeproj` to build the app. The reusable engine and its tests can
also be built with:

```sh
swift test
```

## Codec support and dependencies

| Format | Decode | Encode | Implementation |
| --- | --- | --- | --- |
| JPEG/JPG | Yes | Yes | macOS ImageIO |
| PNG | Yes | Yes | macOS ImageIO |
| HEIC | Yes | Runtime checked | macOS ImageIO |
| TIFF | Yes | Yes | macOS ImageIO |
| AVIF | Yes | Runtime checked | macOS ImageIO |
| WebP | Yes | Yes | ImageIO decode; bundled libwebp 1.5.0 encode |

ImageIO is queried at runtime rather than assuming that an encoder exists.
WebP is decoded by ImageIO and encoded completely offline with libwebp, pinned
at version 1.5.0 under its BSD 3-Clause license.

## File safety rules

With no destination, every result is first encoded to a uniquely named temporary file
on the output volume, reopened, and checked for format and dimensions. The original is
then moved into `original/<relative path>`. Only after that move succeeds is the
validated output moved into place. If placement fails, the original is moved back.
Temporary files are removed on errors and cancellation.

With a destination, source files are never moved. The relative hierarchy is recreated
under the destination. Existing outputs and case-insensitive collisions are rejected
before processing.

Directories named `original` in any capitalization, generated metadata JSON,
temporary files, symbolic links, and a destination nested inside an input are excluded
from discovery.

## Metadata JSON

The schema is version `1`. It contains application version, ISO-8601 date, quality,
selected format, embedded-metadata policy, destination usage, summary counts and
sizes, and deterministic per-image records. Paths are relative. The report is written
atomically with sorted keys and pretty printing.

## Brand

The product icon is © 2026 Grumpy Software. `icon.png` is the single artwork master
and is preserved unchanged. The required macOS sizes in
`Assets.xcassets/AppIcon.appiconset` are generated with
`Scripts/generate-app-icon.sh`. They use an opaque edge-color backing so macOS does
not add a light legacy-icon plate in the Dock. No crop, redraw, text, badge, border,
effect, or extra mask is applied.

## Verification

- Unit, integration and fixture tests cover format detection, paths, collisions,
  safe writes, WebP encoding, multipage TIFF, JSON, bookmarks and codec
  capabilities.
- Fifteen XCUITest scenarios cover every mandatory E2E flow, use isolated
  temporary directories and attach a screenshot on failure.
- Performance tests record discovery, JSON, concurrent batch, progress and
  memory baselines without fragile limits.
- Downloaded fixtures are pinned to source commits and SHA-256 values; normal
  tests never use the network.

Multipage input is preserved when the selected output is TIFF. When converting
a multipage container to a single-image format, the first page is the defined
output.
