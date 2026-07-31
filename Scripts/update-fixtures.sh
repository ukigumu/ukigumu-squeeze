#!/bin/sh
set -eu

download() {
  url="$1"
  destination="$2"
  curl --fail --location --silent --show-error "$url" --output "$destination"
}

download "https://raw.githubusercontent.com/webmproject/libwebp/a4d7a715337ded4451fec90ff8ce79728e04126c/examples/test.webp" "TestFixtures/Sources/WebP/official-test.webp"
download "https://raw.githubusercontent.com/AOMediaCodec/libavif/b71e67f953b2cc905c14869296c72f266cd31683/tests/data/abc_color_irot_alpha_irot.avif" "TestFixtures/Sources/AVIF/alpha.avif"
download "https://raw.githubusercontent.com/AOMediaCodec/libavif/b71e67f953b2cc905c14869296c72f266cd31683/tests/data/white_1x1.avif" "TestFixtures/Sources/AVIF/one-pixel.avif"
download "https://raw.githubusercontent.com/AOMediaCodec/libavif/b71e67f953b2cc905c14869296c72f266cd31683/tests/data/paris_exif_orientation_5.jpg" "TestFixtures/Sources/JPEG/exif-orientation.jpg"
download "https://raw.githubusercontent.com/AOMediaCodec/libavif/b71e67f953b2cc905c14869296c72f266cd31683/tests/data/dog_exif_extended_xmp_icc.jpg" "TestFixtures/Metadata/exif-xmp-icc.jpg"
download "https://raw.githubusercontent.com/AOMediaCodec/libavif/b71e67f953b2cc905c14869296c72f266cd31683/tests/data/draw_points.png" "TestFixtures/Sources/PNG/indexed-transparent.png"
download "https://raw.githubusercontent.com/strukturag/libheif/1a3583bcce77de6d3f8701c0758e3954863681ba/fuzzing/data/corpus/colors-no-alpha.heic" "TestFixtures/Sources/HEIC/colors.heic"
download "https://raw.githubusercontent.com/python-pillow/Pillow/693df7b42c666f88c719f9973be0ad71607328e0/Tests/images/multipage.tiff" "TestFixtures/Sources/TIFF/multipage.tiff"

shasum -a 256 -c TestFixtures/fixtures.sha256
