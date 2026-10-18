#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/VideoTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
validation_target="$(uname -m)-apple-macos26.0"
xcrun swiftc -swift-version 6 -target "$validation_target" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" \
  -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -target "$validation_target" -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/App/VideoLibraryModel.swift Snaprivo/App/VideoEditorModel.swift Snaprivo/Capture/ScreenshotService.swift Snaprivo/Capture/VideoRecording.swift Snaprivo/Capture/VideoRecordingFiles.swift \
  Tests/VideoRecordingChecks.swift Tests/VideoLifecycleChecks.swift Tests/VideoCountdownChecks.swift Tests/VideoLibraryChecks.swift -o "$validation_dir/VideoRecordingChecks"
if (( $# == 0 )) || [[ "$1" == "--permissions" ]]; then
  xcrun swiftc -swift-version 6 -target "$validation_target" -D VIDEO_PERMISSION_CHECKS \
    -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
    -Xlinker -rpath -Xlinker "$validation_dir" \
    Snaprivo/App/VideoLibraryModel.swift Snaprivo/App/VideoEditorModel.swift Snaprivo/Capture/ScreenshotService.swift Snaprivo/Capture/VideoRecording.swift Snaprivo/Capture/VideoRecordingFiles.swift \
    Tests/VideoRecordingChecks.swift Tests/VideoLifecycleChecks.swift Tests/VideoCountdownChecks.swift Tests/VideoLibraryChecks.swift -o "$validation_dir/VideoPermissionChecks"
  if (( $# == 0 )); then
    "$validation_dir/VideoRecordingChecks"
  fi
  "$validation_dir/VideoPermissionChecks"
else
  "$validation_dir/VideoRecordingChecks" "$@"
fi
