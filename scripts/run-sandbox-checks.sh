#!/bin/zsh
set -euo pipefail
check_name="$1"
test_executable="$2"
domain_library="$3"
validation_dir="${test_executable:h}"
test_app="$validation_dir/Snaprivo${check_name}Checks.app"
test_binary="${test_executable:t}"
mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Frameworks"
cp "$test_executable" "$test_app/Contents/MacOS/"
cp "$domain_library" "$test_app/Contents/Frameworks/libSnagForgeDomain.dylib"
python3 - "$test_app" "$check_name" "$test_binary" <<'PY'
import plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.snaprivo.' + sys.argv[2].lower() + 'checks',
    'CFBundleExecutable': sys.argv[3], 'CFBundlePackageType': 'APPL',
    'LSMinimumSystemVersion': '26.0', 'LSUIElement': True}))
(app.parent/'sandbox-test.entitlements').write_bytes(plistlib.dumps({'com.apple.security.app-sandbox': True}))
PY
install_name_tool -change "$domain_library" '@executable_path/../Frameworks/libSnagForgeDomain.dylib' "$test_app/Contents/MacOS/$test_binary"
codesign --force --sign - --timestamp=none "$test_app/Contents/Frameworks/libSnagForgeDomain.dylib"
codesign --force --sign - --timestamp=none --entitlements "$validation_dir/sandbox-test.entitlements" "$test_app"
codesign --verify --deep --strict "$test_app"
shift 3
"$test_app/Contents/MacOS/$test_binary" "$@"
