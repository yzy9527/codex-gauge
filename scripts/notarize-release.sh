#!/bin/bash

set -euo pipefail

DMG_PATH="${1:-}"
if [[ -z "${DMG_PATH}" || ! -f "${DMG_PATH}" ]]; then
  echo "用法：notarize-release.sh <已签名的 dmg>" >&2
  exit 2
fi

notary_arguments=()
if [[ -n "${APPLE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  notary_arguments+=(--keychain-profile "${APPLE_NOTARY_KEYCHAIN_PROFILE}")
else
  : "${APPLE_NOTARY_KEY_ID:?缺少 APPLE_NOTARY_KEY_ID}"
  : "${APPLE_NOTARY_ISSUER_ID:?缺少 APPLE_NOTARY_ISSUER_ID}"
  : "${APPLE_NOTARY_PRIVATE_KEY_PATH:?缺少 APPLE_NOTARY_PRIVATE_KEY_PATH}"
  notary_arguments+=(
    --key "${APPLE_NOTARY_PRIVATE_KEY_PATH}"
    --key-id "${APPLE_NOTARY_KEY_ID}"
    --issuer "${APPLE_NOTARY_ISSUER_ID}"
  )
fi

codesign --verify --verbose=2 "${DMG_PATH}"
xcrun notarytool submit "${DMG_PATH}" "${notary_arguments[@]}" --wait
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"

DMG_DIRECTORY="$(cd "$(dirname "${DMG_PATH}")" && pwd)"
DMG_NAME="$(basename "${DMG_PATH}")"
(
  cd "${DMG_DIRECTORY}"
  LC_ALL=C LANG=C shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
)

echo "公证和 Gatekeeper 验证通过：${DMG_PATH}"
