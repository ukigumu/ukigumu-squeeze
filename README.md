# Ukigumu Squeeze

<p align="center">
  <img src="icon.png" alt="Ukigumu Squeeze icon" width="160">
</p>

Ukigumu Squeeze is a native macOS photo and video compressor by **Ukigumu**. Drop files or folders onto the window, choose a photo quality or a video preset, and write smaller files without sending anything off your Mac.

**Privacy is local only.** There is no account, no telemetry, no analytics, no uploads, and no network requests. Photos and videos are discovered, encoded, and written on the machine that runs the app.

Requires **macOS 14** or later.

## Download

Install the Mac app from the latest GitHub Release. You do not need to clone this repository.

**[Download Ukigumu Squeeze](https://github.com/ukigumu/ukigumu-squeeze/releases/latest)**

The release attaches a `.dmg`. Open it and drag **Ukigumu Squeeze** onto **Applications**.

v0 builds are ad-hoc signed and not notarized. If macOS blocks the app, Control-click (or right-click) it and choose Open. See `Documentation/dmg.md`.

## Features

- Drop files and folders, or select them with the native file panel.
- Recursive content-based discovery that does not follow symbolic links.
- Photo input: JPEG/JPG, PNG, AVIF, HEIC, TIFF, and WebP.
- Video input: MP4, MOV, M4V, plus AVI and MPEG when the container can be identified.
- JPEG, PNG, AVIF, HEIC, and TIFF output through ImageIO when the encoder is available at runtime.
- WebP output through the bundled, local libwebp 1.5.0 encoder.
- Video presets modeled on HandBrake's simple choices: Smaller File, Fast 1080p, Social, High Quality, and Custom. Each preset maps to codec, AAC audio, a resolution cap, and a size versus quality lean. Not a wall of encoder knobs.
- Photos still use the quality slider and resolution controls. Videos use the selected preset. Both share the same local cancellable queue, per-item progress, destination, and before/after sizes.
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
| MOV | Yes | HEVC keeps MOV; H.264 writes MP4 | macOS AVFoundation |
| M4V | Yes | HEVC keeps M4V; H.264 writes MP4 | macOS AVFoundation |
| AVI / MPEG | Yes | Written as MP4 | Identified locally; remuxed to a writable container |

ImageIO is queried at runtime rather than assuming that an encoder exists. WebP is decoded by ImageIO and encoded completely offline with libwebp 1.5.0, under its BSD 3-Clause license. The license text is in `TestFixtures/Licenses/libwebp-COPYING.txt`. Video uses the system AVFoundation export session on the same Mac. Named presets pick codec, AAC audio, resolution cap, and size versus quality.

H.264 presets (Smaller File, Fast 1080p, Social, and Custom with a Smaller or Balanced lean) always write MP4. Apple's H.264 export presets are MPEG-4 only, so a source `.mov` still compresses, but the output container is MP4. High Quality (HEVC) keeps a writable source container (MP4, MOV, or M4V). AVI and MPEG remap to MP4. Choosing a photo format still compresses videos on that video path. Choosing MP4 or MOV leaves photos on their photo path. See `Documentation/codecs.md` for the codec decision record.

## Video presets

These are HandBrake-style names, not a HandBrake clone. Squeeze stays a simple local queue.

| Preset | Codec | Audio | Resolution cap | Size vs quality | Output |
| --- | --- | --- | --- | --- | --- |
| Smaller File | H.264 | AAC | 720p | Smallest | MP4 |
| Fast 1080p | H.264 | AAC | 1080p | Balanced | MP4 |
| Social | H.264 | AAC | 1080p | Small, shareable | MP4 |
| High Quality | HEVC when available | AAC | Source | Best look | Keep MOV or MP4 |
| Custom | H.264 or HEVC from the lean | AAC | 720p, 1080p, 1440p, or source | Smaller, Balanced, or Higher | MP4 for H.264; keep container for HEVC |

AVFoundation does not expose ffmpeg CRF. Quality leans map to system export presets (Low / Medium / High / HEVC High). Audio is AAC through the same local export session.

### Try a sample MP4 or MOV

The repo includes tiny local fixtures. They are not downloaded.

```
TestFixtures/Sources/Video/solid.mp4
TestFixtures/Sources/Video/solid.mov
TestFixtures/Sources/Video/hd.mp4
```

1. Open `UkigumuSqueeze.xcodeproj` and run the **UkigumuSqueeze** scheme.
2. Drop `solid.mp4` or `solid.mov` onto the window. For a 1080p cap check, drop `hd.mp4`.
3. Pick Smaller File, Fast 1080p, or Social. The Format column shows MOV to MP4 for those H.264 presets. Choose a destination folder if you want the source left untouched.
4. Press Compress. The queue shows Waiting / Encoding with a percent, then Done, plus before and after sizes. If a row fails, Status stays "Error" and a subtitle under it shows `ProcessingResult.error` (the export session failure). Click the row or the info button to open the same string in an alert. Hover on the info button also shows it.

Automated coverage: `swift test` and the XCUITest `testVideoCompressionWithDestination`.

## Build and test

The app requires macOS 14 or later and Xcode with a Swift 6 toolchain.

Most people should use the [Download](#download) DMG. Contributors on a Mac can build a Release disk image with:

```sh
make dmg
```

That produces `dist/UkigumuSqueeze-<version>.dmg`. See `Documentation/dmg.md`.

Open `UkigumuSqueeze.xcodeproj` in Xcode on a Mac and run the **UkigumuSqueeze** scheme to build the app.

The reusable engine and its tests can also be built from the repository root with Swift Package Manager. There is no JavaScript toolchain and no `pnpm` workflow.

```sh
swift test
```

That command runs the unit, integration, fixture, and performance test targets defined in `Package.swift`. XCUITests live in the Xcode project and need a Mac GUI session.

After launch, drop photos, videos, or folders (or use Choose files or folders). Pick a video preset or photo quality, set an optional destination, then Compress. The queue shows each file's status and before/after size. Show in Finder opens the written files. Nothing is uploaded.

## File safety

With no destination, every result is first encoded to a uniquely named temporary file, reopened, and checked for format and dimensions. Photos encode next to the output. Videos encode inside the app container so `AVAssetExportSession` does not write through a sandbox extension, then the validated file is moved into place. The original is then moved into `original/<relative path>`. If placement fails, the original is moved back. Temporary files are removed on errors and cancellation.

Dropped or chosen files need security-scoped access for the whole encode. If that grant is missing, Squeeze asks once for the containing folder (or the destination folder) with the native open panel, bookmarks the grant, and retries. Cancelling the panel shows a folder-access error instead of "You don't have permission."

With a destination, source files are never moved. The relative hierarchy is recreated under the destination. Existing outputs and case-insensitive collisions are rejected before processing.

Directories named `original` in any capitalization, generated metadata JSON, temporary files, symbolic links, and a destination nested inside an input are excluded from discovery.

Multipage input is preserved when the selected output is TIFF. When converting a multipage container to a single-image format, the first page is the defined output.

## Metadata reports

Optional JSON export writes `ukigumu-squeeze-metadata.json`. The schema is version `1`. It contains application version, ISO-8601 date, quality, selected format, embedded-metadata policy, destination usage, summary counts and sizes, and deterministic per-file records. Paths are relative. The report is written atomically with sorted keys and pretty printing. See `Documentation/metadata-schema.md`.

## Icon

The product icon is © 2026 Ukigumu. `icon.png` is the single artwork master and is preserved unchanged. The required macOS sizes in `Sources/UkigumuSqueezeApp/Resources/Assets.xcassets/AppIcon.appiconset` are generated with `Scripts/generate-app-icon.sh`. They use an opaque edge-color backing so macOS does not add a light legacy-icon plate in the Dock. No crop, redraw, text, badge, border, effect, or extra mask is applied.

## Verification

- Unit, integration, and fixture tests cover format detection, paths, collisions, safe writes, WebP encoding, video discovery and local export, mixed photo/video batches, multipage TIFF, JSON, bookmarks, and codec capabilities.
- Eighteen XCUITest scenarios cover the mandatory end-to-end flows, including video and mixed batches, use isolated temporary directories, and attach a screenshot on failure.
- Performance tests record discovery, JSON, concurrent batch, progress, and memory baselines without fragile limits. See `Documentation/performance-baselines.md`.
- Downloaded fixtures are pinned to source commits and SHA-256 values. Normal tests never use the network.
