#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
fixture_app="$PWD/build/ScrollFixture.app"
mkdir -p "$fixture_app/Contents/MacOS" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
xcrun swiftc -swift-version 6 -parse-as-library Tests/Fixtures/ScrollFixtureApp.swift -o "$fixture_app/Contents/MacOS/ScrollFixture"
cat > "$fixture_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ScrollFixture</string>
<key>CFBundleIdentifier</key><string>com.snaprivo.scrollfixture</string>
<key>CFBundleName</key><string>Snaprivo Scroll Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
