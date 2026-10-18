#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/CaptureTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" \
  -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  Snaprivo/Features/SelectionGrips.swift \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/Capture/ScreenshotService.swift Snaprivo/Capture/ScreenshotSelector.swift \
  Tests/CaptureSelectionChecks.swift -o "$validation_dir/CaptureSelectionChecks"
"$validation_dir/CaptureSelectionChecks"
