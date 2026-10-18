#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app_bundle="${1:-$PWD/build/LocalizationBuild/Build/Products/Debug/Snaprivo.app}"
validation_dir="$PWD/build/LocalizationTests"
test_host="$validation_dir/LocalizationHost.app"
mkdir -p "$validation_dir" "$test_host/Contents/MacOS" "$test_host/Contents/Resources" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
cp -R "$app_bundle/Contents/Resources/en.lproj" "$app_bundle/Contents/Resources/de.lproj" \
  "$app_bundle/Contents/Resources/SnagForgeDomain_SnagForgeDomain.bundle" "$test_host/Contents/Resources/"
/usr/libexec/PlistBuddy -c 'Clear dict' -c 'Add CFBundleIdentifier string com.snaprivo.localization-tests' \
  -c 'Add CFBundleExecutable string LocalizationChecks' -c 'Add CFBundlePackageType string APPL' \
  -c 'Add CFBundleDevelopmentRegion string en' "$test_host/Contents/Info.plist"
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/App/AppPreferences.swift Snaprivo/App/CaptureShortcuts.swift Snaprivo/App/SupportFeedback.swift \
  Snaprivo/Capture/ScreenshotService.swift Tests/LocalizationChecks.swift \
  -o "$test_host/Contents/MacOS/LocalizationChecks"
"$test_host/Contents/MacOS/LocalizationChecks" en -AppleLanguages '(en)' -AppleLocale en_US
"$test_host/Contents/MacOS/LocalizationChecks" de -AppleLanguages '(de)' -AppleLocale de_DE
"$test_host/Contents/MacOS/LocalizationChecks" en -AppleLanguages '(fr)' -AppleLocale fr_FR
