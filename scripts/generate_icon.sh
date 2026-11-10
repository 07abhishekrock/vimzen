#!/bin/bash
set -e

SRC_IMAGE="$1"
if [ -z "${SRC_IMAGE}" ] || [ ! -f "${SRC_IMAGE}" ]; then
    echo "Usage: ./scripts/generate_icon.sh <path-to-png-image>"
    echo "Example: ./scripts/generate_icon.sh my_logo.png"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEST_DIR="${REPO_ROOT}/vimzen/Resources"
mkdir -p "${DEST_DIR}"

ICONSET_DIR="/tmp/VimzenAppIcon.iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

echo "==> Generating iconset variants from ${SRC_IMAGE}..."
sips -z 16 16     "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32     "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64     "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256   "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512   "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${SRC_IMAGE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

echo "==> Compiling native macOS AppIcon.icns..."
iconutil -c icns "${ICONSET_DIR}" -o "${DEST_DIR}/AppIcon.icns"
rm -rf "${ICONSET_DIR}"

echo "✓ Created: ${DEST_DIR}/AppIcon.icns"
echo "Run ./scripts/release.sh to package Vimzen with your new icon!"
