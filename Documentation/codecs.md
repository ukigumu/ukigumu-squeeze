# Codec decision record

The app uses Apple ImageIO, Core Graphics, and Uniform Type Identifiers for
JPEG/JPG, PNG, AVIF, HEIC and TIFF. These are system frameworks and add no
redistributable license.

At startup/encode time, writable identifiers are obtained from
`CGImageDestinationCopyTypeIdentifiers()`. This is necessary because the development
host and the minimum supported macOS 14 runtime can expose different encoders.

The development host reports JPEG, PNG, AVIF, HEIC and TIFF as writable. AVIF
and HEIC capability tests query those identifiers explicitly, and the E2E suite
validates PNG→AVIF, AVIF→PNG and HEIC→JPEG.

WebP output uses `libwebp-Xcode` 1.5.0, pinned exactly through Swift Package
Manager. It packages the official libwebp encoder and is BSD 3-Clause licensed;
the license is stored in `TestFixtures/Licenses/libwebp-COPYING.txt`. It is
necessary because ImageIO on the development macOS reads WebP but does not
advertise a WebP destination. Ukigumu Squeeze calls the local `WebPEncodeRGBA`
API directly and performs no network access at runtime.

Video compression uses AVFoundation `AVAssetExportSession` on the same Mac.
No ffmpeg binary is bundled and no file is uploaded. The UI exposes HandBrake-like
presets instead of encoder knobs. Each preset maps to concrete local settings:

- Smaller File: H.264, AAC, Low export preset, fit within 1280x720
- Fast 1080p: H.264, AAC, Medium export preset, fit within 1920x1080
- Social: H.264, AAC, Low export preset, fit within 1920x1080, shareable
- High Quality: HEVC High when available, AAC, source resolution
- Custom: cap (720p / 1080p / 1440p / source) plus Smaller / Balanced / Higher

Compatible system export presets are queried at runtime, including
`determineCompatibility` of each preset with the asset and file type. H.264
presets write MP4 even when the source is MOV: Apple's Low / Medium / High and
size-based H.264 presets are MPEG-4, and many camera `.mov` files are not
compatible with a QuickTime output file type. HEVC High Quality keeps a writable
source container (MOV, MP4, or M4V). Temporary encode files use the planned
container extension so AVFoundation does not reject a `.tmp` URL. AVI and MPEG
can be discovered from their containers but are written as MP4 because those
input containers are not writable through the system export session. Photo
quality and photo resolution controls do not change video output. The queue
reports per-item export progress from `AVAssetExportSession.progress`. Failed
rows keep a non-empty error string for the Status column.

App Sandbox only grants dropped or panel-chosen files while
`startAccessingSecurityScopedResource()` stays active. Video encode holds that
access on the source, folder root, destination, and `original/` paths for the
whole `AVAssetExportSession` lifetime, including `exportAsynchronously`.
Bookmarks are resolved before `AVURLAsset` is created. The encode temp is
written inside the app container, then moved to the destination under the same
scoped access. Sandbox permission errors surface as a re-choose message and
keep the system detail.
