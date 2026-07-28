#!/usr/bin/env bash
# Remove CI keychain / provisioning profiles created by setup_signing.sh.
# Safe to run even if nothing was imported. Never prints secret values.
set -euo pipefail
set +x

KEYCHAIN_NAME="${KEYCHAIN_NAME:-build.keychain-db}"

security delete-keychain "$KEYCHAIN_NAME" 2>/dev/null || true
rm -f \
  "$HOME/Library/MobileDevice/Provisioning Profiles/ci.mobileprovision" \
  "$HOME/Library/MobileDevice/Provisioning Profiles/ci-mac.provisionprofile" \
  2>/dev/null || true

echo "Signing cleanup finished."
