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
No ffmpeg binary is bundled and no file is uploaded. Compatible export presets
are queried at runtime. Quality maps to Low, Medium, and High (HEVC High when
the asset supports it). Resolution uses the same calculator as photos and is
applied through a local video composition. AVI and MPEG can be discovered from
their containers but are written as MP4 because those input containers are not
writable through the system export session.
