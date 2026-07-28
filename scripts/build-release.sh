#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/dist}"
DMG_NAME="CodexGauge-${VERSION}-arm64.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
CHECKSUM_PATH="${DMG_PATH}.sha256"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "版本号必须采用语义化格式，例如 0.1.0" >&2
  exit 2
fi

if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "BUILD_NUMBER 必须是正整数" >&2
  exit 2
fi

for command_name in xcodebuild hdiutil ditto lipo shasum codesign; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "缺少构建命令：${command_name}" >&2
    exit 1
  fi
done

mkdir -p "${OUTPUT_DIR}"
rm -f "${DMG_PATH}" "${CHECKSUM_PATH}"

RELEASE_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-gauge-release.XXXXXX")"
cleanup() {
  case "${RELEASE_WORK_DIR}" in
    */codex-gauge-release.*) rm -rf "${RELEASE_WORK_DIR}" ;;
  esac
}
trap cleanup EXIT

ARCHIVE_PATH="${RELEASE_WORK_DIR}/CodexGauge.xcarchive"
STAGING_DIR="${RELEASE_WORK_DIR}/dmg"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/CodexGauge.app"
STAGED_APP_PATH="${STAGING_DIR}/CodexGauge.app"

build_settings=(
  "ARCHS=arm64"
  "ONLY_ACTIVE_ARCH=NO"
  "MARKETING_VERSION=${VERSION}"
  "CURRENT_PROJECT_VERSION=${BUILD_NUMBER}"
)

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  build_settings+=(
    "CODE_SIGNING_ALLOWED=YES"
    "CODE_SIGNING_REQUIRED=YES"
    "CODE_SIGN_STYLE=Manual"
    "CODE_SIGN_IDENTITY=${CODESIGN_IDENTITY}"
    "OTHER_CODE_SIGN_FLAGS=--timestamp"
  )
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    build_settings+=("DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}")
  fi
else
  build_settings+=(
    "CODE_SIGNING_ALLOWED=YES"
    "CODE_SIGNING_REQUIRED=YES"
    "CODE_SIGN_STYLE=Manual"
    "CODE_SIGN_IDENTITY=-"
    "AD_HOC_CODE_SIGNING_ALLOWED=YES"
  )
fi

xcodebuild \
  -project "${PROJECT_ROOT}/CodexGauge.xcodeproj" \
  -scheme CodexGauge \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${RELEASE_WORK_DIR}/DerivedData" \
  -archivePath "${ARCHIVE_PATH}" \
  clean archive \
  "${build_settings[@]}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "归档中没有生成 CodexGauge.app" >&2
  exit 1
fi

ARCHITECTURES="$(lipo -archs "${APP_PATH}/Contents/MacOS/CodexGauge")"
if [[ "${ARCHITECTURES}" != "arm64" ]]; then
  echo "发布二进制架构异常：${ARCHITECTURES}" >&2
  exit 1
fi

mkdir -p "${STAGING_DIR}"
ditto "${APP_PATH}" "${STAGED_APP_PATH}"
ln -s /Applications "${STAGING_DIR}/Applications"

codesign --verify --deep --strict --verbose=2 "${STAGED_APP_PATH}"

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  if ! codesign --display --verbose=4 "${STAGED_APP_PATH}" 2>&1 | grep '^Signature=adhoc$' >/dev/null; then
    echo "应用未使用预期的 ad-hoc 签名" >&2
    exit 1
  fi
fi

hdiutil create \
  -volname "Codex Gauge" \
  -srcfolder "${STAGING_DIR}" \
  -format UDZO \
  -ov \
  "${DMG_PATH}"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "${CODESIGN_IDENTITY}" "${DMG_PATH}"
  codesign --verify --verbose=2 "${DMG_PATH}"
fi

(
  cd "${OUTPUT_DIR}"
  LC_ALL=C LANG=C shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
)

echo "已生成：${DMG_PATH}"
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "提示：App 使用无需开发者账号的 ad-hoc 签名，DMG 未经 Apple 公证；首次启动需要用户在系统设置中允许打开。"
fi
