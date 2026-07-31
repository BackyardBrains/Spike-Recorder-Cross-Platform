#!/usr/bin/env bash
# Sync third_party/aqnwb/src + macos processing plugin into all platforms
# (including web). Web keeps sz_stubs.cpp.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PLUGIN="$ROOT/PLUGINS/nwbfile_plugin"
AQNWB="$ROOT/third_party/aqnwb/src"
REF="$PLUGIN/macos/Classes/src"

sync_into() {
  local dest="$1"
  mkdir -p "$dest"
  local tmp; tmp="$(mktemp -d)"
  for f in nwbfile_plugin.c nwbfile_plugin.h sz_stubs.cpp; do
    [[ -f "$dest/$f" ]] && cp "$dest/$f" "$tmp/" || true
  done
  rm -rf "$dest/io" "$dest/nwb" "$dest/spec"
  rm -f "$dest/Channel.cpp" "$dest/Channel.hpp" "$dest/Types.hpp" "$dest/Utils.hpp"
  rsync -a --exclude '.DS_Store' "$AQNWB/" "$dest/"
  cp "$REF/nwbfile_processing_plugin.cpp" "$dest/"
  cp "$REF/nwbfile_processing_plugin.hpp" "$dest/"
  for f in nwbfile_plugin.c nwbfile_plugin.h sz_stubs.cpp; do
    [[ -f "$tmp/$f" ]] && cp "$tmp/$f" "$dest/" || true
  done
  [[ -f "$dest/nwbfile_plugin.h" ]] || cp "$REF/nwbfile_plugin.h" "$dest/" 2>/dev/null || true
  [[ -f "$dest/nwbfile_plugin.c" ]] || cp "$REF/nwbfile_plugin.c" "$dest/" 2>/dev/null || true
  rm -rf "$tmp"
  echo "Synced -> $dest"
}

[[ -d "$AQNWB" ]] || { echo "Missing $AQNWB"; exit 1; }
[[ -f "$REF/nwbfile_processing_plugin.cpp" ]] || { echo "Missing reference processing plugin"; exit 1; }

sync_into "$PLUGIN/ios/Classes/src"
sync_into "$PLUGIN/android/src/main/cpp/src"
sync_into "$PLUGIN/windows/src"
sync_into "$PLUGIN/linux/src"
sync_into "$PLUGIN/web/src"
# Also refresh macos AqNWB tree (keep processing as-is already in REF)
rsync -a --exclude '.DS_Store' --exclude 'nwbfile_processing_plugin.*' --exclude 'nwbfile_plugin.*' "$AQNWB/" "$REF/"
echo "Done (including web)."
