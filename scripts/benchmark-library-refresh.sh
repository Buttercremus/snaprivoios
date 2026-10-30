#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/LibraryRefreshBenchmark"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -O -swift-version 6 -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" \
  -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -O -parse-as-library -swift-version 6 -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" Tests/LibraryRefreshBenchmark.swift \
  -o "$validation_dir/LibraryRefreshBenchmark"
"$validation_dir/LibraryRefreshBenchmark"
