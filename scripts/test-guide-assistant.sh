#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/GuideAssistantTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
validation_target="$(uname -m)-apple-macos26.0"
xcrun swiftc -swift-version 6 -target "$validation_target" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -target "$validation_target" -whole-module-optimization \
  -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/Editor/EditorRenderer.swift Snaprivo/Editor/GuideExporter.swift Snaprivo/Editor/TextRecognitionService.swift \
  Snaprivo/App/GuideModel.swift Snaprivo/App/GuideAssistantService.swift Snaprivo/App/GuideAssistantModel.swift \
  Tests/GuideAssistantChecks.swift -o "$validation_dir/GuideAssistantChecks"
args=("$@")
if [[ "${1:-}" == "--sandbox" ]]; then
  args=("${args[@]:1}")
  ./scripts/run-sandbox-checks.sh GuideAssistant "$validation_dir/GuideAssistantChecks" "$validation_dir/libSnagForgeDomain.dylib" "${args[@]}"
else
  "$validation_dir/GuideAssistantChecks" "${args[@]}"
fi
