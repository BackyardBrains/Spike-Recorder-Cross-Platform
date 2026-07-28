#!/usr/bin/env bash
# Fail if credential-looking files or private-key material are tracked / present for commit.
# Safe to run locally and in CI. Never prints secret contents — only paths / pattern names.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAILED=0

deny_path_regex='(scripts/testflight/env\.local|(^|/)\.env(\.|$)|AuthKey_.*\.p8|\.p8$|\.p12$|\.pem$|\.mobileprovision$|\.provisionprofile$|\.jks$|key\.properties$|(^|/)secrets/|(^|/)\.secrets/|credentials\.json$|service-account.*\.json$)'

echo "==> Scanning git-tracked files for credential paths..."
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ "$path" =~ $deny_path_regex ]]; then
    echo "REFUSING: tracked credential-looking path: $path" >&2
    FAILED=1
  fi
done < <(git ls-files)

echo "==> Scanning staged / unstaged working tree for credential paths..."
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  # strip status prefix from git status --porcelain
  file="${path:3}"
  file="${file##* -> }"
  if [[ "$file" =~ $deny_path_regex ]]; then
    echo "REFUSING: working-tree credential-looking path: $file" >&2
    FAILED=1
  fi
done < <(git status --porcelain)

echo "==> Scanning tracked text for private-key / PKCS markers..."
# Only scan likely text sources; skip large/vendor trees.
SCAN_PATHS=(
  fastlane
  scripts
  .github
  ios/ExportOptions.plist
  macos/ExportOptions.plist
  macos/Runner/Configs
)
CONTENT_PATTERNS=(
  'BEGIN PRIVATE KEY'
  'BEGIN RSA PRIVATE KEY'
  'BEGIN EC PRIVATE KEY'
  'BEGIN OPENSSH PRIVATE KEY'
  'APP_STORE_CONNECT_KEY_CONTENT=-----'
)

for pattern in "${CONTENT_PATTERNS[@]}"; do
  matches="$(git grep -n -I -F -- "$pattern" -- "${SCAN_PATHS[@]}" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    # Allow only documented placeholders in env.example (commented, no real key body)
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      file="${line%%:*}"
      if [[ "$file" == "scripts/testflight/env.example" ]]; then
        continue
      fi
      echo "REFUSING: private-key-like content in: $line" >&2
      FAILED=1
    done <<<"$matches"
  fi
done

if [[ "$FAILED" -ne 0 ]]; then
  echo "Credential safety check failed. Remove secrets from the tree; use GitHub Secrets / env.local (gitignored)." >&2
  exit 1
fi

echo "Credential safety check passed."
