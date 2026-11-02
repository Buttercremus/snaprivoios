#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Native operation of the full video editor with a synthetic clip; screenshots for visual review.
validation_dir="$PWD/build/VideoEditorUI"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
validation_target="$(uname -m)-apple-macos26.0"
xcrun swiftc -swift-version 6 -target "$validation_target" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -whole-module-optimization -target "$validation_target" -D WORKFLOW_CHECKS \
  -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/App/*.swift Snaprivo/Capture/*.swift Snaprivo/Editor/*.swift Snaprivo/Features/*.swift \
  Tests/Fixtures/SyntheticVideo.swift Tests/VideoEditorUIChecks.swift -o "$validation_dir/VideoEditorUIChecks"
"$validation_dir/VideoEditorUIChecks" "${1:-$validation_dir/Screens}"
