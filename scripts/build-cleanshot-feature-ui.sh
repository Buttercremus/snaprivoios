#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/CleanShotFeatureUI"
validation_app="$validation_dir/SnaprivoCleanShotFeatureUI.app"
mkdir -p "$validation_app/Contents/MacOS" "$validation_app/Contents/Frameworks" "$validation_app/Contents/Resources" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
target="$(uname -m)-apple-macos26.0"
xcrun swiftc -swift-version 6 -target "$target" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -whole-module-optimization -target "$target" -D WORKFLOW_CHECKS \
  -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  Snaprivo/App/*.swift Snaprivo/Capture/*.swift Snaprivo/Editor/*.swift Snaprivo/Features/*.swift \
  Tests/Fixtures/CleanShotFeatureUI.swift -o "$validation_app/Contents/MacOS/CleanShotFeatureUI"
resource_app="$PWD/build/CleanShotBuild/Build/Products/Debug/Snaprivo.app"
test -d "$resource_app/Contents/Resources"
cp -R "$resource_app/Contents/Resources/." "$validation_app/Contents/Resources/"
cp "$validation_dir/libSnagForgeDomain.dylib" "$validation_app/Contents/Frameworks/"
python3 - "$validation_app" <<'PY'
import plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
(app / "Contents/Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "com.snaprivo.featurevalidation",
    "CFBundleName": "Snaprivo CleanShot Feature Fixture",
    "CFBundleExecutable": "CleanShotFeatureUI",
    "CFBundlePackageType": "APPL",
    "LSMinimumSystemVersion": "26.0",
}))
PY
codesign --force --deep --sign - "$validation_app"
printf '%s\n' "$validation_app"
