#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
command -v ffmpeg >/dev/null || { print -u2 'Local developer tool ffmpeg is required (not shipped in Snaprivo).'; exit 1; }
fixture_app="$PWD/build/AVSyncFixture.app"
mkdir -p "$fixture_app/Contents/MacOS" "$fixture_app/Contents/Resources" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
# A single media timeline provides simultaneous optical/acoustic references.
# Pulses last 200 ms, begin at 0.5 s, and recur every two seconds.
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "color=c=black:s=640x360:r=30:d=32,drawbox=x=160:y=90:w=320:h=180:color=white:t=fill:enable='gte(mod(t,2),0.5)*lt(mod(t,2),0.7)'" \
  -f lavfi -i "aevalsrc=exprs='if(gte(mod(t,2),0.5)*lt(mod(t,2),0.7),0.3*sin(2*PI*1000*t),0)':s=48000:d=32" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 160k -ac 2 \
  -movflags +faststart -shortest "$fixture_app/Contents/Resources/AVSync.mp4"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos26.0" -parse-as-library \
  Tests/Fixtures/AVSyncFixtureApp.swift -o "$fixture_app/Contents/MacOS/AVSyncFixture"
cat > "$fixture_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AVSyncFixture</string>
<key>CFBundleIdentifier</key><string>com.snaprivo.avsyncfixture</string>
<key>CFBundleName</key><string>Snaprivo AV Sync Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
print "$fixture_app"
