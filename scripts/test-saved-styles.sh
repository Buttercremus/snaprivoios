#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/SavedStyleTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos26.0" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos26.0" \
  -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/App/AppPreferences.swift Snaprivo/Editor/EditorModel.swift Snaprivo/Editor/EditorRenderer.swift \
  Tests/SavedStyleChecks.swift -o "$validation_dir/SavedStyleChecks"
"$validation_dir/SavedStyleChecks"
style_test_suite="Snaprivo-StyleRestart-$(uuidgen)"
"$validation_dir/SavedStyleChecks" --persist-write "$style_test_suite"
"$validation_dir/SavedStyleChecks" --persist-read "$style_test_suite"
