#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
source_icon="$project_dir/icon.png"
asset_dir="$project_dir/Sources/UkigumuSqueezeApp/Resources/Assets.xcassets/AppIcon.appiconset"
platform_background="#405744"

if ! command -v magick >/dev/null 2>&1; then
    print -u2 "ImageMagick is required to generate the macOS app icon."
    exit 1
fi

for size in 16 32 64 128 256 512 1024; do
    # macOS adds a light legacy-icon plate around transparent app icons.
    # Compositing the source over its edge color makes each platform asset
    # opaque so the system applies only its own icon shape.
    magick "$source_icon" \
        -background "$platform_background" \
        -alpha remove \
        -alpha off \
        -filter Lanczos \
        -resize "${size}x${size}" \
        -strip \
        "$asset_dir/AppIcon-$size.png"
done
