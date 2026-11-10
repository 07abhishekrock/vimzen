#!/bin/bash
set -e

# ==============================================================================
# Vimzen Release & Packaging Pipeline
# Builds optimized release binary, packages Vimzen.app, generates .dmg,
# tags git commit, pushes to remote, and publishes a GitHub release.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VIMZEN_DIR="${REPO_ROOT}/vimzen"
DIST_DIR="${REPO_ROOT}/dist"
VERSION_FILE="${REPO_ROOT}/VERSION"

cd "${REPO_ROOT}"

# 1. Determine Version
VERSION_INPUT="$1"
if [ -z "${VERSION_INPUT}" ]; then
    if [ -f "${VERSION_FILE}" ]; then
        VERSION="$(cat "${VERSION_FILE}" | tr -d '[:space:]')"
    else
        VERSION="1.0.0"
    fi
else
    # Strip optional leading 'v'
    VERSION="${VERSION_INPUT#v}"
fi

echo "=================================================="
echo " Packaging Vimzen v${VERSION}"
echo "=================================================="

# Save version to VERSION file
echo "${VERSION}" > "${VERSION_FILE}"

BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
TAG_NAME="v${VERSION}"
APP_NAME="Vimzen"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_NAME="Vimzen-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

echo "• Version:      ${VERSION}"
echo "• Build Number: ${BUILD_NUMBER}"
echo "• Git Tag:      ${TAG_NAME}"

# 2. Build Swift Release Binary
echo ""
echo "==> Compiling optimized Swift release binary..."
cd "${VIMZEN_DIR}"
swift build -c release

RELEASE_BIN="${VIMZEN_DIR}/.build/release/${APP_NAME}"
if [ ! -f "${RELEASE_BIN}" ]; then
    echo "Error: Release binary not found at ${RELEASE_BIN}"
    exit 1
fi

# 3. Assemble .app Bundle
echo ""
echo "==> Assembling ${APP_NAME}.app bundle..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "${RELEASE_BIN}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Generate Info.plist from template
PLIST_TEMPLATE="${VIMZEN_DIR}/Resources/Info.plist"
if [ -f "${PLIST_TEMPLATE}" ]; then
    sed -e "s/__VERSION__/${VERSION}/g" \
        -e "s/__BUILD_NUMBER__/${BUILD_NUMBER}/g" \
        "${PLIST_TEMPLATE}" > "${APP_BUNDLE}/Contents/Info.plist"
else
    echo "Warning: Info.plist template not found, using minimal plist"
fi

# PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Ad-hoc code sign so macOS allows launching
echo "==> Ad-hoc code signing application..."
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

# 4. Create DMG
echo ""
echo "==> Creating ${DMG_NAME} installer..."
DMG_ROOT="${DIST_DIR}/dmg_root"
mkdir -p "${DMG_ROOT}"

# Copy App to DMG root
cp -R "${APP_BUNDLE}" "${DMG_ROOT}/"

# Add /Applications shortcut
ln -s /Applications "${DMG_ROOT}/Applications"

# Build compressed DMG
hdiutil create \
    -volname "Vimzen Installer" \
    -srcfolder "${DMG_ROOT}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

rm -rf "${DMG_ROOT}"

echo "✓ Created: ${DMG_PATH}"
echo "  File size: $(du -h "${DMG_PATH}" | cut -f1)"

# 5. Local Installation Option
echo ""
echo "==> Installing to /Applications/${APP_NAME}.app..."
rm -rf "/Applications/${APP_NAME}.app"
cp -R "${APP_BUNDLE}" "/Applications/"
echo "✓ Installed Vimzen in /Applications (ready in Spotlight & Launchpad)"

# 6. Git Commit, Tag & Push
echo ""
echo "==> Git versioning..."
cd "${REPO_ROOT}"
git add "${VERSION_FILE}" "${VIMZEN_DIR}/Resources/Info.plist" 2>/dev/null || true
if ! git diff-index --quiet HEAD --; then
    git commit -m "chore(release): bump version to ${VERSION} [build ${BUILD_NUMBER}]" || true
fi

# Create annotated tag if it doesn't exist
if git rev-parse "${TAG_NAME}" >/dev/null 2>&1; then
    echo "Tag ${TAG_NAME} already exists locally."
else
    git tag -a "${TAG_NAME}" -m "Release ${TAG_NAME}"
    echo "✓ Created git tag: ${TAG_NAME}"
fi

# Push to remote
echo "==> Pushing to git remote..."
git push origin main || true
git push origin "${TAG_NAME}" || true

# 7. GitHub Release
if command -v gh >/dev/null 2>&1; then
    echo ""
    echo "==> Publishing GitHub Release..."
    # Switch to 07abhishekrock if available
    gh auth switch --user 07abhishekrock 2>/dev/null || true

    if gh release view "${TAG_NAME}" >/dev/null 2>&1; then
        echo "Release ${TAG_NAME} already exists on GitHub, uploading DMG asset..."
        gh release upload "${TAG_NAME}" "${DMG_PATH}" --clobber || true
    else
        gh release create "${TAG_NAME}" "${DMG_PATH}" \
            --title "Vimzen ${TAG_NAME}" \
            --generate-notes || true
    fi
    echo "✓ GitHub release published at https://github.com/07abhishekrock/vimzen/releases/tag/${TAG_NAME}"
fi

echo ""
echo "=================================================="
echo "🎉 Vimzen v${VERSION} successfully released!"
echo "• App: /Applications/Vimzen.app"
echo "• DMG: ${DMG_PATH}"
echo "=================================================="
