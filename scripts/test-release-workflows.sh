#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/ReleaseWorkflowTests"
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
  Tests/ReleaseWorkflowChecks.swift Tests/ProAccessChecks.swift -o "$validation_dir/ReleaseWorkflowChecks"
if [[ "${1:-}" == "--sandbox" ]]; then
  ./scripts/run-sandbox-checks.sh ReleaseWorkflow "$validation_dir/ReleaseWorkflowChecks" "$validation_dir/libSnagForgeDomain.dylib"
else
  "$validation_dir/ReleaseWorkflowChecks"
fi
