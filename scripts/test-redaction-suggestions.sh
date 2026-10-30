#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/RedactionSuggestionChecks"
mkdir -p "$validation_dir" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos26.0" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos26.0" \
  -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" \
  Snaprivo/Editor/EditorModel.swift Snaprivo/Editor/EditorRenderer.swift Snaprivo/Editor/TextRecognitionService.swift \
  Snaprivo/Editor/RedactionSuggestionModel.swift Tests/RedactionSuggestionChecks.swift \
  -o "$validation_dir/RedactionSuggestionChecks"
if [[ "${1:-}" == "--sandbox" ]]; then
  # Disposable, self-contained host: verifies Vision with the actual App Sandbox,
  # without screen/microphone/network entitlements or access to the user's library.
  test_app="$validation_dir/SnaprivoRedactionChecks.app"
  mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Frameworks"
  cp "$validation_dir/RedactionSuggestionChecks" "$test_app/Contents/MacOS/"
  cp "$validation_dir/libSnagForgeDomain.dylib" "$test_app/Contents/Frameworks/"
  python3 - "$test_app" <<'PY'
import plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.snaprivo.redactionchecks', 'CFBundleExecutable': 'RedactionSuggestionChecks',
    'CFBundlePackageType': 'APPL', 'LSMinimumSystemVersion': '26.0', 'LSUIElement': True}))
(app.parent/'redaction-test.entitlements').write_bytes(plistlib.dumps({'com.apple.security.app-sandbox': True}))
PY
  install_name_tool -change "$validation_dir/libSnagForgeDomain.dylib" \
    '@executable_path/../Frameworks/libSnagForgeDomain.dylib' "$test_app/Contents/MacOS/RedactionSuggestionChecks"
  codesign --force --sign - --timestamp=none "$test_app/Contents/Frameworks/libSnagForgeDomain.dylib"
  codesign --force --sign - --timestamp=none --entitlements "$validation_dir/redaction-test.entitlements" "$test_app"
  codesign --verify --deep --strict "$test_app"
  "$test_app/Contents/MacOS/RedactionSuggestionChecks"
else
  "$validation_dir/RedactionSuggestionChecks"
fi
