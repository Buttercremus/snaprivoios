#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/ReleaseWorkflowTests"
validation_app="$validation_dir/SnaprivoWorkflowUI.app"
mkdir -p "$validation_app/Contents/MacOS" "$validation_app/Contents/Frameworks" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
# Build the matching domain module; a previous test run may predate current sources.
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos26.0" -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
xcrun swiftc -swift-version 6 -whole-module-optimization -target "$(uname -m)-apple-macos26.0" -D WORKFLOW_CHECKS \
  -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  Snaprivo/App/*.swift Snaprivo/Capture/*.swift Snaprivo/Editor/*.swift Snaprivo/Features/*.swift \
  Tests/Fixtures/ReleaseWorkflowUI.swift -o "$validation_app/Contents/MacOS/WorkflowUI"
mkdir -p "$validation_app/Contents/Resources"
cp -R "$PWD/build/ProPackage/Build/Products/Debug/Snaprivo.app/Contents/Resources/." "$validation_app/Contents/Resources/"
cp "$validation_dir/libSnagForgeDomain.dylib" "$validation_app/Contents/Frameworks/"
python3 - "$validation_app" <<'PLIST'
import plistlib,sys
from pathlib import Path
(Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.snaprivo.workflowui','CFBundleName':'Snaprivo Workflow UI','CFBundleExecutable':'WorkflowUI','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'26.0'}))
PLIST
codesign --force --deep --sign - "$validation_app"
