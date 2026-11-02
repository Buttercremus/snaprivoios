#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/QuickLookTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
validation_target="$(uname -m)-apple-macos26.0"
xcrun swiftc -swift-version 6 -target "$validation_target" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -target "$validation_target" -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" Snaprivo/Editor/EditorRenderer.swift \
  Extensions/QuickLookShared/ProjectPreviewRenderer.swift Tests/QuickLookChecks.swift -o "$validation_dir/QuickLookChecks"
if [[ "${1:-}" == "--sandbox" ]]; then
  shift
  ./scripts/run-sandbox-checks.sh QuickLook "$validation_dir/QuickLookChecks" "$validation_dir/libSnagForgeDomain.dylib"
else
  "$validation_dir/QuickLookChecks"
fi
if [[ "${1:-}" == "--system" ]]; then
  fixture="$validation_dir/SystemFixture-$(uuidgen).snaprivo"
  "$validation_dir/QuickLookChecks" --export-fixture "$fixture"
  thumbnail_dir="$validation_dir/SystemThumbnails-$(uuidgen)"
  mkdir -p "$thumbnail_dir"
  /usr/bin/qlmanage -t -x -c com.snaprivo.project -s 256 -o "$thumbnail_dir" "$fixture"
  thumbnails=("$thumbnail_dir"/*.png(N))
  (( ${#thumbnails} == 1 ))
  "$validation_dir/QuickLookChecks" --verify-thumbnail "$thumbnails[1]"
fi
