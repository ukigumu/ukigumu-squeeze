# Fixture and codec licenses

The downloaded corpus is pinned by commit and SHA-256 in
`TestFixtures/fixtures-manifest.json`.

- WebP codec and fixture: WebP project, BSD 3-Clause. See `libwebp-COPYING.txt`.
- AVIF, PNG and JPEG fixtures: AOMediaCodec/libavif test corpus. See
  `libavif-LICENSE.txt`; individual provenance is documented by libavif's
  `tests/data/README.md`.
- HEIC fixture: libheif fuzzing corpus. See `libheif-COPYING.txt`.
- Multipage TIFF: Pillow test corpus, HPND license. See `Pillow-LICENSE.txt`.
- Synthetic fixtures: generated for UkigumuSqueeze and © 2026 Ukigumu.

No fixture is downloaded during normal tests. `Scripts/update-fixtures.sh` is a
manual development-only updater and refuses content whose checksum changes.
