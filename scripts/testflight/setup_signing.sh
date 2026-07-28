#!/usr/bin/env bash
# Install code-signing material for CI (GitHub Actions macos runner).
# Expects base64-encoded .p12 and (optional) provisioning profiles in env.
# Never echoes secret values. Temp material is deleted on exit.
set -euo pipefail
# Never enable xtrace while secrets are in the environment.
set +x
unset HISTFILE || true

KEYCHAIN_NAME="${KEYCHAIN_NAME:-build.keychain-db}"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -base64 32)}"
P12_PASSWORD="${P12_PASSWORD:-}"
CERT_PATH=""
PROFILE_PATHS=()

cleanup() {
  if [[ -n "${CERT_PATH}" && -f "${CERT_PATH}" ]]; then
    rm -f "${CERT_PATH}"
  fi
}
trap cleanup EXIT

if [[ -z "${BUILD_CERTIFICATE_BASE64:-}" ]]; then
  echo "BUILD_CERTIFICATE_BASE64 not set — assuming Xcode automatic signing / local identities."
  exit 0
fi

umask 077
CERT_PATH="$(mktemp "${TMPDIR:-/tmp}/build_certificate.XXXXXX.p12")"
# Write without printing payload
printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 --decode >"$CERT_PATH"
chmod 600 "$CERT_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME" || true
security set-keychain-settings -lut 21600 "$KEYCHAIN_NAME"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security import "$CERT_PATH" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_NAME"
security list-keychains -d user -s "$KEYCHAIN_NAME" login.keychain
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
rm -f "$CERT_PATH"
CERT_PATH=""

if [[ -n "${BUILD_PROVISION_PROFILE_BASE64:-}" ]]; then
  mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
  PROFILE_PATH="$HOME/Library/MobileDevice/Provisioning Profiles/ci.mobileprovision"
  printf '%s' "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode >"$PROFILE_PATH"
  chmod 600 "$PROFILE_PATH"
  PROFILE_PATHS+=("$PROFILE_PATH")
fi

if [[ -n "${BUILD_MAC_PROVISION_PROFILE_BASE64:-}" ]]; then
  mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
  PROFILE_PATH="$HOME/Library/MobileDevice/Provisioning Profiles/ci-mac.provisionprofile"
  printf '%s' "$BUILD_MAC_PROVISION_PROFILE_BASE64" | base64 --decode >"$PROFILE_PATH"
  chmod 600 "$PROFILE_PATH"
  PROFILE_PATHS+=("$PROFILE_PATH")
fi

echo "Code-signing material imported (keychain=$KEYCHAIN_NAME). Secrets were not printed."
