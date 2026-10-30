#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/ProjectOpeningBenchmark"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
target="$(uname -m)-apple-macos26.0"
xcrun swiftc -swift-version 6 -target "$target" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -whole-module-optimization -target "$target" -D WORKFLOW_CHECKS \
  -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/App/*.swift Snaprivo/Capture/*.swift Snaprivo/Editor/*.swift Snaprivo/Features/*.swift \
  Tests/ProjectOpeningBenchmark.swift -o "$validation_dir/ProjectOpeningBenchmark"
"$validation_dir/ProjectOpeningBenchmark"
