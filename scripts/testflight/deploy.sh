#!/usr/bin/env bash
# Deploy Spike Recorder to TestFlight (iOS and/or macOS).
# Triggered by push to `ailoop` via GitHub Actions, or run locally:
#   set -a && source scripts/testflight/env.local && set +a && ./scripts/testflight/deploy.sh
#
# Credentials must come from the environment / GitHub Secrets — never from tracked files.
set -euo pipefail
# Refuse shell xtrace so secrets cannot leak into logs.
set +x
set +o xtrace 2>/dev/null || true
unset HISTFILE || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PLATFORM="${1:-all}" # all | ios | macos
BUILD_NAME="${BUILD_NAME:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

bash "$ROOT/scripts/testflight/check_no_secrets.sh"

if [[ -z "$BUILD_NAME" || -z "$BUILD_NUMBER" ]]; then
  VERSION_LINE="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
  PUB_NAME="${VERSION_LINE%%+*}"
  PUB_NUMBER="${VERSION_LINE##*+}"
  BUILD_NAME="${BUILD_NAME:-$PUB_NAME}"
  if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    BUILD_NUMBER="${BUILD_NUMBER:-$GITHUB_RUN_NUMBER}"
  else
    BUILD_NUMBER="${BUILD_NUMBER:-$PUB_NUMBER}"
  fi
fi

export BUILD_NAME BUILD_NUMBER
export SKIP_WAITING_FOR_BUILD_PROCESSING="${SKIP_WAITING_FOR_BUILD_PROCESSING:-true}"

echo "==> TestFlight deploy"
echo "    platform=$PLATFORM  version=$BUILD_NAME+$BUILD_NUMBER"
echo "    root=$ROOT"
echo "    (credential values are never printed)"

require_asc_secrets() {
  if [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
    echo "Missing APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_ISSUER_ID" >&2
    exit 1
  fi
  if [[ -z "${APP_STORE_CONNECT_KEY_CONTENT:-}" && -z "${APP_STORE_CONNECT_KEY_PATH:-}" ]]; then
    echo "Missing APP_STORE_CONNECT_KEY_CONTENT or APP_STORE_CONNECT_KEY_PATH" >&2
    exit 1
  fi
  # Keep AuthKey material outside the git work tree
  if [[ -n "${APP_STORE_CONNECT_KEY_PATH:-}" ]]; then
    if [[ ! -f "$APP_STORE_CONNECT_KEY_PATH" ]]; then
      echo "APP_STORE_CONNECT_KEY_PATH does not exist" >&2
      exit 1
    fi
    key_abs="$(cd "$(dirname "$APP_STORE_CONNECT_KEY_PATH")" && pwd)/$(basename "$APP_STORE_CONNECT_KEY_PATH")"
    case "$key_abs" in
      "$ROOT"/*)
        echo "REFUSING: APP_STORE_CONNECT_KEY_PATH is inside the repo. Keep .p8 outside the tree." >&2
        exit 1
        ;;
    esac
  fi
}

ensure_flutter() {
  if ! command -v flutter >/dev/null 2>&1; then
    echo "flutter not on PATH" >&2
    exit 1
  fi
  flutter pub get
}

run_ios() {
  echo "==> iOS TestFlight"
  require_asc_secrets
  ensure_flutter
  (cd "$ROOT" && fastlane ios beta)
}

run_macos() {
  echo "==> macOS TestFlight"
  require_asc_secrets
  ensure_flutter
  (cd "$ROOT" && fastlane mac beta)
}

case "$PLATFORM" in
  all)
    STATUS=0
    if ! run_ios; then
      STATUS=$?
      if [[ "${ALLOW_PARTIAL_DEPLOY:-false}" != "true" ]]; then
        exit "$STATUS"
      fi
      echo "iOS deploy failed; continuing because ALLOW_PARTIAL_DEPLOY=true" >&2
    fi
    if ! run_macos; then
      STATUS=$?
      if [[ "${ALLOW_PARTIAL_DEPLOY:-false}" != "true" ]]; then
        exit "$STATUS"
      fi
      echo "macOS deploy failed; ALLOW_PARTIAL_DEPLOY=true so exiting with $STATUS" >&2
    fi
    exit "$STATUS"
    ;;
  ios)
    run_ios
    ;;
  macos|mac)
    run_macos
    ;;
  *)
    echo "Usage: $0 [all|ios|macos]" >&2
    exit 2
    ;;
esac
