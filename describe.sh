#!/usr/bin/env bash
echo "Script started."

#
# describe.sh
# -----------
# Combines Flutter/Dart files and C++ implementation files from '.' (including subdirs)
# into ONE FILE, excluding build artifacts, temporary files, and dependencies
# Also includes a tree output (no summary), then code excerpts.

OUTPUT_FILE="flutter_project.txt"

echo "Generating $OUTPUT_FILE..."

# Common directories/files to exclude:
# - build related: build, Debug, Release, cmake-build-*, CMakeFiles, winrt
# - IDE/tools: .dart_tool, .pub, .git, .idea, .vscode
# - platform specific: android/build, ios/Pods, windows/out
# - generated files: generated_*, .flutter-plugins*
# - temp/cache: .tlog, .log, *.cache
EXCLUDE_PATTERN='build|\.dart_tool|\.pub|\.git|\.DS_Store|.*\.lock|\.idea|cmake-build-debug|Debug|Release|\.tlog|\.log|CMakeFiles|winrt|generated_*|\.flutter-plugins.*|android/gradle|ios/Pods|windows/out|\.vscode|\.tlog|\.cache'

###
# (1) Print the 'tree' view.
###
{
  echo "===== Project Tree ====="
  tree . \
    -I "${EXCLUDE_PATTERN}" \
    -P '*.dart|*.cpp|*.h|*.cc|*.cmake|pubspec.yaml|*.gradle' \
    --prune \
    --noreport
  echo -e "\n===== Begin Code Excerpts =====\n"
} > "$OUTPUT_FILE"

echo "Collected tree output."

###
# (2) Collect paths in the same order 'tree' uses.
###
tree_files=$(
  tree -fi . \
    -I "${EXCLUDE_PATTERN}" \
    -P '*.dart|*.cpp|*.h|*.cc|*.cmake|pubspec.yaml|*.gradle' \
    --prune \
    --noreport \
  | sed -e '/\/$/d' \
  | sed -e '/^\.$/d' \
  | sed -e '/\.(tlog|pdb|obj|exe|ilk|exp|lib|dll|manifest)$/d' \
  | awk '!seen[$0]++'
)

echo "Files collected: $tree_files"

###
# (3) Loop over each file and append to the output
###
while IFS= read -r file; do
  echo "Processing file: $file"
  if [ -f "$file" ]; then
    echo "----- BEGIN $file -----" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo -e "\n----- END $file -----\n" >> "$OUTPUT_FILE"
  else
    echo "File not found: $file"
  fi
done <<< "$tree_files"

echo "Done. See '$OUTPUT_FILE' for the combined codebase."