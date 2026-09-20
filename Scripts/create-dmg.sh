#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
app_only=0
version=${VERSION:-}
output_dir=${OUTPUT_DIR:-"$root/dist"}
derived_data=${DERIVED_DATA:-"$root/build/DerivedData"}
app_name="Ukigumu Squeeze.app"
product_name="Ukigumu Squeeze"
scheme="UkigumuSqueeze"
project="$root/UkigumuSqueeze.xcodeproj"

usage() {
    cat <<'EOF'
Create a Release build of Ukigumu Squeeze and a drag-to-Applications DMG.

Usage:
  Scripts/create-dmg.sh [--app-only] [--version VERSION] [--output-dir DIR]

Environment:
  VERSION        DMG version label (default: current git tag without v, else 1.0.0)
  OUTPUT_DIR     Destination directory (default: dist)
  DERIVED_DATA   xcodebuild derived data path

Requires macOS with Xcode and hdiutil. Signing is ad-hoc for v0.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --app-only) app_only=1 ;;
        --version) version=$2; shift ;;
        --output-dir) output_dir=$2; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

if [ -z "$version" ]; then
    if tag=$(git -C "$root" describe --tags --exact-match 2>/dev/null); then
        version=${tag#v}
    else
        version=1.0.0
    fi
fi
version=${version#v}

require_mac() {
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "xcodebuild was not found. Run this on a Mac with Xcode." >&2
        exit 1
    fi
}

require_mac
mkdir -p "$output_dir" "$derived_data"

echo "Building Release $app_name (ad-hoc signed, version $version)"
xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    ENABLE_HARDENED_RUNTIME=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    MARKETING_VERSION="$version" \
    build

app_path="$derived_data/Build/Products/Release/$app_name"
if [ ! -d "$app_path" ]; then
    echo "Release app was not produced at $app_path" >&2
    exit 1
fi

if [ "$app_only" -eq 1 ]; then
    echo "App: $app_path"
    exit 0
fi

if ! command -v hdiutil >/dev/null 2>&1; then
    echo "hdiutil was not found. Run this on macOS." >&2
    exit 1
fi

stage=$(mktemp -d "${TMPDIR:-/tmp}/ukigumu-squeeze-dmg.XXXXXX")
cleanup() {
    rm -rf "$stage"
}
trap cleanup EXIT

cp -R "$app_path" "$stage/$app_name"
ln -s /Applications "$stage/Applications"

dmg_name="UkigumuSqueeze-$version.dmg"
dmg_path="$output_dir/$dmg_name"
rm -f "$dmg_path"

echo "Creating $dmg_path"
hdiutil create \
    -volname "$product_name" \
    -srcfolder "$stage" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$dmg_path"

echo "DMG: $dmg_path"
echo "Drag $app_name onto Applications after opening the disk image."
