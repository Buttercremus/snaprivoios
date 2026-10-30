#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/ImageOutputTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos26.0" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos26.0" \
  -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/Editor/PresentationBackground.swift Snaprivo/Editor/PresentationPresets.swift Snaprivo/Editor/ImageOutput.swift Snaprivo/Editor/EditorRenderer.swift \
  Tests/ImageOutputChecks.swift -o "$validation_dir/ImageOutputChecks"
"$validation_dir/ImageOutputChecks" "$validation_dir/comparison.png"
