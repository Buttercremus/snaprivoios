#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
fixture_app="$PWD/build/VideoValidationFixture.app"
mkdir -p "$fixture_app/Contents/MacOS" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos26.0" -parse-as-library \
  Tests/Fixtures/VideoValidationFixtureApp.swift -o "$fixture_app/Contents/MacOS/VideoValidationFixture"
python3 - "$fixture_app" <<'PY'
import plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({
 'CFBundleExecutable':'VideoValidationFixture', 'CFBundleIdentifier':'com.snaprivo.videovalidationfixture',
 'CFBundleName':'Snaprivo V04 Silent Fixture', 'CFBundlePackageType':'APPL',
 'LSMinimumSystemVersion':'26.0', 'NSHighResolutionCapable':True}))
PY
print "$fixture_app"
