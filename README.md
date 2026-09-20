# Ukigumu Squeeze

<p align="center">
  <img src="icon.png" alt="Ukigumu Squeeze icon" width="160">
</p>

Ukigumu Squeeze is a native macOS photo and video compressor by **Ukigumu**. Drop files or folders onto the window, choose a format and quality, and write smaller files without sending anything off your Mac.

**Privacy is local only.** There is no account, no telemetry, no analytics, no uploads, and no network requests. Photos and videos are discovered, encoded, and written on the machine that runs the app.

Requires **macOS 14** or later.

## Features

- Drop files and folders, or select them with the native file panel.
- Recursive content-based discovery that does not follow symbolic links.
- Photo input: JPEG/JPG, PNG, AVIF, HEIC, TIFF, and WebP.
- Video input: MP4, MOV, M4V, plus AVI and MPEG when the container can be identified.
- JPEG, PNG, AVIF, HEIC, and TIFF output through ImageIO when the encoder is available at runtime.
- WebP output through the bundled, local libwebp 1.5.0 encoder.
- MP4 and MOV output through local AVFoundation export presets. Quality uses Low / Medium / High (HEVC when available). The same quality, resolution, destination, and before/after size flow as photos.
- Concurrent, cancellable processing with bounded structured concurrency.
- Optional destination that leaves source files untouched.
- Recoverable in-place writes through a lowercase `original` tree.
- Temporary-file encoding, reopen/format/dimension validation, and rollback.
- Exact `.jpg` / `.jpeg` preservation when the format is unchanged.
- Collision detection before processing.
- Embedded metadata preservation or removal, independent of JSON export.
- Deterministic, atomic `ukigumu-squeeze-metadata.json` reports without absolute paths.
- App Sandbox with user-selected read/write access.
- Stable accessibility identifiers on primary controls.

## Codec support

| Format | Decode | Encode | Implementation |
| --- | --- | --- | --- |
| JPEG/JPG | Yes | Yes | macOS ImageIO |
| PNG | Yes | Yes | macOS ImageIO |
| HEIC | Yes | Runtime checked | macOS ImageIO |
| TIFF | Yes | Yes | macOS ImageIO |
| AVIF | Yes | Runtime checked | macOS ImageIO |
| WebP | Yes | Yes | ImageIO decode; bundled libwebp 1.5.0 encode |
| MP4 | Yes | Yes | macOS AVFoundation |
| MOV | Yes | Yes | macOS AVFoundation |
| M4V | Yes | Keep original | macOS AVFoundation |
| AVI / MPEG | Yes | Written as MP4 | Identified locally; remuxed to a writable container |

ImageIO is queried at runtime rather than assuming that an encoder exists. WebP is decoded by ImageIO and encoded completely offline with libwebp 1.5.0, under its BSD 3-Clause license. The license text is in `TestFixtures/Licenses/libwebp-COPYING.txt`. Video uses the system AVFoundation export session on the same Mac. Keep original leaves a writable video container as-is (MP4, MOV, M4V) and remaps AVI or MPEG to MP4. Choosing a photo format still compresses videos in their writable container. Choosing MP4 or MOV leaves photos on their photo path. See `Documentation/codecs.md` for the codec decision record.

## Build and test

The app requires macOS 14 or later and Xcode with a Swift 6 toolchain.

Open `UkigumuSqueeze.xcodeproj` in Xcode on a Mac and run the **UkigumuSqueeze** scheme to build the app.

The reusable engine and its tests can also be built from the repository root with Swift Package Manager. There is no JavaScript toolchain and no `pnpm` workflow.

```sh
swift test
```

That command runs the unit, integration, fixture, and performance test targets defined in `Package.swift`. XCUITests live in the Xcode project and need a Mac GUI session.

After launch, drop photos, videos, or folders (or use Choose files or folders), set quality / format / optional destination, then Compress. The queue shows before and after sizes. Show in Finder opens the written files. Nothing is uploaded.

## File safety

With no destination, every result is first encoded to a uniquely named temporary file on the output volume, reopened, and checked for format and dimensions. The original is then moved into `original/<relative path>`. Only after that move succeeds is the validated output moved into place. If placement fails, the original is moved back. Temporary files are removed on errors and cancellation.

With a destination, source files are never moved. The relative hierarchy is recreated under the destination. Existing outputs and case-insensitive collisions are rejected before processing.

Directories named `original` in any capitalization, generated metadata JSON, temporary files, symbolic links, and a destination nested inside an input are excluded from discovery.

Multipage input is preserved when the selected output is TIFF. When converting a multipage container to a single-image format, the first page is the defined output.

## Metadata reports

Optional JSON export writes `ukigumu-squeeze-metadata.json`. The schema is version `1`. It contains application version, ISO-8601 date, quality, selected format, embedded-metadata policy, destination usage, summary counts and sizes, and deterministic per-file records. Paths are relative. The report is written atomically with sorted keys and pretty printing. See `Documentation/metadata-schema.md`.

## Icon

The product icon is © 2026 Ukigumu. `icon.png` is the single artwork master and is preserved unchanged. The required macOS sizes in `Sources/UkigumuSqueezeApp/Resources/Assets.xcassets/AppIcon.appiconset` are generated with `Scripts/generate-app-icon.sh`. They use an opaque edge-color backing so macOS does not add a light legacy-icon plate in the Dock. No crop, redraw, text, badge, border, effect, or extra mask is applied.

## Verification

- Unit, integration, and fixture tests cover format detection, paths, collisions, safe writes, WebP encoding, video discovery and local export, mixed photo/video batches, multipage TIFF, JSON, bookmarks, and codec capabilities.
- Seventeen XCUITest scenarios cover the mandatory end-to-end flows, including video and mixed batches, use isolated temporary directories, and attach a screenshot on failure.
- Performance tests record discovery, JSON, concurrent batch, progress, and memory baselines without fragile limits. See `Documentation/performance-baselines.md`.
- Downloaded fixtures are pinned to source commits and SHA-256 values. Normal tests never use the network.
