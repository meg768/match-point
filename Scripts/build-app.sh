#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="Match Room"
EXECUTABLE_NAME="MatchRoom"
APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
STAGING_APP_DIR="/tmp/${APP_NAME}.app"
CONTENTS_DIR="${STAGING_APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
BUILD_DIR="${ROOT_DIR}/.build/${CONFIGURATION}"

if [[ "${CONFIGURATION}" != "debug" && "${CONFIGURATION}" != "release" ]]; then
  echo "Usage: Scripts/build-app.sh [debug|release]" >&2
  exit 1
fi

cd "${ROOT_DIR}"

if [[ "${CONFIGURATION}" == "release" ]]; then
  swift build -c release
else
  swift build
fi

rm -rf "${STAGING_APP_DIR}" "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
cp "${ROOT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp -R "${ROOT_DIR}/Resources/Flags" "${RESOURCES_DIR}/Flags"
chmod +x "${MACOS_DIR}/${EXECUTABLE_NAME}"

dot_clean "${STAGING_APP_DIR}" 2>/dev/null || true
xattr -cr "${STAGING_APP_DIR}"
xattr -d com.apple.FinderInfo "${STAGING_APP_DIR}" 2>/dev/null || true
xattr -d "com.apple.fileprovider.fpfs#P" "${STAGING_APP_DIR}" 2>/dev/null || true
xattr -dr com.apple.FinderInfo "${STAGING_APP_DIR}" 2>/dev/null || true
find "${STAGING_APP_DIR}" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "${STAGING_APP_DIR}" -exec xattr -d "com.apple.fileprovider.fpfs#P" {} \; 2>/dev/null || true
find "${STAGING_APP_DIR}" -exec xattr -c {} \; 2>/dev/null || true
find "${STAGING_APP_DIR}" -name '._*' -delete

signed=false
for _ in {1..6}; do
  xattr -cr "${STAGING_APP_DIR}" 2>/dev/null || true
  xattr -c "${STAGING_APP_DIR}" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "${STAGING_APP_DIR}" 2>/dev/null || true
  xattr -d "com.apple.fileprovider.fpfs#P" "${STAGING_APP_DIR}" 2>/dev/null || true

  if codesign --force --deep --sign - "${STAGING_APP_DIR}"; then
    signed=true
    break
  fi
  sleep 1
done

if [[ "${signed}" != true ]]; then
  echo "Failed to sign ${STAGING_APP_DIR}" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "${STAGING_APP_DIR}"

mkdir -p "${ROOT_DIR}/dist"
ditto "${STAGING_APP_DIR}" "${APP_DIR}"

verified=false
for _ in {1..6}; do
  xattr -c "${APP_DIR}" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "${APP_DIR}" 2>/dev/null || true
  xattr -d "com.apple.fileprovider.fpfs#P" "${APP_DIR}" 2>/dev/null || true

  if codesign --verify --deep --strict --verbose=2 "${APP_DIR}"; then
    verified=true
    break
  fi
  sleep 1
done

if [[ "${verified}" != true ]]; then
  echo "Failed to verify ${APP_DIR}" >&2
  exit 1
fi

echo "Built ${APP_DIR}"
