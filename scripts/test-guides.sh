#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/GuideTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/Editor/EditorRenderer.swift Snaprivo/Editor/GuideExporter.swift Snaprivo/App/GuideModel.swift \
  Tests/GuideChecks.swift -o "$validation_dir/GuideChecks"
if [[ "${1:-}" == "--sandbox" ]]; then
  ./scripts/run-sandbox-checks.sh Guides "$validation_dir/GuideChecks" "$validation_dir/libSnagForgeDomain.dylib"
  runner="$validation_dir/SnaprivoGuidesChecks.app/Contents/MacOS/GuideChecks"
else
  SNAPRIVO_GUIDE_QA_OUTPUT="$validation_dir" "$validation_dir/GuideChecks"
  runner="$validation_dir/GuideChecks"
fi
restart_key="Snaprivo-Guide-Restart-$(uuidgen)"
"$runner" --write "$restart_key"
"$runner" --read "$restart_key"
