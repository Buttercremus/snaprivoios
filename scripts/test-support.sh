#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/SupportTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -swift-version 6 Snaprivo/App/SupportFeedback.swift Tests/SupportFeedbackChecks.swift \
  -o "$validation_dir/SupportFeedbackChecks"
"$validation_dir/SupportFeedbackChecks" "${1:-Snaprivo/Resources/Info.plist}"
