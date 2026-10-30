#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/EditorToolbarTests"
test_host="$validation_dir/ToolbarChecks.app"
mkdir -p "$test_host/Contents/MacOS" "$test_host/Contents/Resources" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
cp -R "$PWD/build/AnnotationBuild/Build/Products/Debug/Snaprivo.app/Contents/Resources/en.lproj" \
  "$PWD/build/AnnotationBuild/Build/Products/Debug/Snaprivo.app/Contents/Resources/de.lproj" "$test_host/Contents/Resources/"
/usr/libexec/PlistBuddy -c 'Clear dict' -c 'Add CFBundleIdentifier string com.snaprivo.toolbarchecks' \
  -c 'Add CFBundleExecutable string EditorToolbarChecks' -c 'Add CFBundlePackageType string APPL' \
  -c 'Add CFBundleDevelopmentRegion string en' "$test_host/Contents/Info.plist"
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -whole-module-optimization -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/App/AppPreferences.swift Snaprivo/App/CaptureShortcuts.swift Snaprivo/Capture/ScreenshotService.swift \
  Snaprivo/Editor/EditorModel.swift Snaprivo/Editor/EditorRenderer.swift Snaprivo/Features/EditorToolPalette.swift \
  Tests/EditorToolbarChecks.swift -o "$test_host/Contents/MacOS/EditorToolbarChecks"
"$test_host/Contents/MacOS/EditorToolbarChecks" "$validation_dir" -AppleLanguages '(de)' -AppleLocale de_DE
"$test_host/Contents/MacOS/EditorToolbarChecks" "$validation_dir" -AppleLanguages '(en)' -AppleLocale en_US
