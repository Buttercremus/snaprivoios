#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/VideoEditingTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
validation_target="$(uname -m)-apple-macos26.0"
xcrun swiftc -swift-version 6 -target "$validation_target" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" \
  -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -target "$validation_target" -D VIDEO_EDITING_CHECKS -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/App/VideoLibraryModel.swift Snaprivo/App/VideoEditorModel.swift Snaprivo/Capture/ScreenshotService.swift Snaprivo/Capture/VideoRecording.swift Snaprivo/Capture/VideoRecordingFiles.swift \
  Tests/VideoRecordingChecks.swift Tests/VideoLifecycleChecks.swift Tests/VideoCountdownChecks.swift Tests/VideoLibraryChecks.swift Tests/VideoEditingChecks.swift -o "$validation_dir/VideoEditingRunner"
if [[ "${1:-}" == "--sandbox" ]]; then
  ./scripts/run-sandbox-checks.sh VideoEditing "$validation_dir/VideoEditingRunner" "$validation_dir/libSnagForgeDomain.dylib"
  runner="$validation_dir/SnaprivoVideoEditingChecks.app/Contents/MacOS/VideoEditingRunner"
else
  "$validation_dir/VideoEditingRunner"
  runner="$validation_dir/VideoEditingRunner"
fi
restart_key="VideoEditing-$(uuidgen)"
"$runner" --write "$restart_key"
"$runner" --read "$restart_key"
