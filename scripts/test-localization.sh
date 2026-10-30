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
fixture_identifier="com.snaprivo.localization-tests.$(uuidgen)"
/usr/libexec/PlistBuddy -c 'Clear dict' -c "Add CFBundleIdentifier string $fixture_identifier" \
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

# Real process restarts use the fixture's native per-app language preference,
# without command-line language overrides or changes to the user's Mac/app.
language_host="$test_host/Contents/MacOS/LocalizationChecks"
trap '"$language_host" language-preference cleanup' EXIT
"$language_host" language-preference baseline "$validation_dir/system-language.txt"
"$language_host" language-preference write en
"$language_host" language-preference read en en
"$language_host" language-preference write de
"$language_host" language-preference read de de
"$language_host" language-preference clear
"$language_host" language-preference read-system "$validation_dir/system-language.txt"
"$language_host" language-preference native-regional
"$language_host" language-preference read de de
