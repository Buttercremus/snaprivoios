#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/SettingsTests"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" \
  -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  Snaprivo/App/StorageLocations.swift \
  Snaprivo/Features/SelectionGrips.swift \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/App/AppPreferences.swift Snaprivo/App/CaptureShortcuts.swift Snaprivo/App/WorkspaceModel.swift Snaprivo/App/CompleteBackup.swift Snaprivo/App/ProPurchaseModel.swift Snaprivo/App/VideoLibraryModel.swift Snaprivo/App/VideoEditorModel.swift Snaprivo/App/GuideModel.swift Snaprivo/Editor/GuideExporter.swift Snaprivo/App/LibrarySearchModel.swift Snaprivo/Editor/TextRecognitionService.swift \
  Snaprivo/Features/ShortcutRecorder.swift Snaprivo/Editor/EditorRenderer.swift Snaprivo/Editor/EditorModel.swift \
  Snaprivo/Capture/VideoRecording.swift Snaprivo/Capture/VideoRecordingFiles.swift Snaprivo/Capture/ScreenshotCoordinator.swift Snaprivo/Capture/ScreenshotService.swift Snaprivo/Capture/ScreenshotSelector.swift \
  Tests/SettingsChecks.swift Tests/StorageLocationChecks.swift -o "$validation_dir/SettingsChecks"
"$validation_dir/SettingsChecks"
