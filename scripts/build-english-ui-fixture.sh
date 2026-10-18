#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
fixture_language="${1:-en}"
case "$fixture_language" in
  en) fixture_name="SnaprivoEnglishQA"; fixture_id="com.snaprivo.englishuifixture"; fixture_title="Snaprivo English QA"; fixture_directory="EnglishUIFixture" ;;
  de) fixture_name="SnaprivoGermanQA"; fixture_id="com.snaprivo.germanuifixture"; fixture_title="Snaprivo German QA"; fixture_directory="GermanUIFixture" ;;
  *) print -u2 'Use en or de for the isolated UI fixture.'; exit 1 ;;
esac
validation_dir="$PWD/build/$fixture_directory"
fixture_app="$validation_dir/$fixture_name.app"
fixture_derived="${SNAPRIVO_QA_DERIVED_DATA:-$PWD/build/LocalizationBuild}"
source_app="$fixture_derived/Build/Products/Debug/Snaprivo.app"
mkdir -p "$fixture_app/Contents/MacOS" "$fixture_app/Contents/Resources" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
# Single-language host resources avoid changes to the user's macOS preferences.
cp -R "$source_app/Contents/Resources/$fixture_language.lproj" \
  "$source_app/Contents/Resources/SnagForgeDomain_SnagForgeDomain.bundle" "$fixture_app/Contents/Resources/"
python3 - "$validation_dir" "$fixture_app" "$fixture_name" "$fixture_id" "$fixture_title" "$fixture_language" <<'PY'
import plistlib, sys
from pathlib import Path
validation, app = map(Path, sys.argv[1:3])
name, identifier, title, language = sys.argv[3:]
source = Path('Snaprivo/App/SnagForgeApp.swift').read_text()
source = source.replace('@State private var workspace = WorkspaceModel()', '@State private var workspace = EnglishUIFixture.makeWorkspace()')
source = source.replace('CaptureCommands(workspace: workspace)', 'CaptureCommands(workspace: workspace)\n            EnglishUIFixtureCommands(workspace: workspace)', 1)
(validation/'EnglishApp.swift').write_text(source)
info = {'CFBundleExecutable':name, 'CFBundleIdentifier':identifier,
        'CFBundleName':title, 'CFBundlePackageType':'APPL', 'CFBundleDevelopmentRegion':language,
        'CFBundleShortVersionString':'0.1.0', 'CFBundleVersion':'2', 'LSMinimumSystemVersion':'26.0', 'NSHighResolutionCapable':True}
info['UTExportedTypeDeclarations'] = plistlib.loads(Path('Snaprivo/Resources/Info.plist').read_bytes())['UTExportedTypeDeclarations']
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
accessor="$fixture_derived/Build/Intermediates.noindex/SnagForgeDomain.build/Debug/SnagForgeDomain-t.build/DerivedSources/resource_bundle_accessor.swift"
xcrun swiftc -target "$(uname -m)-apple-macos26.0" -swift-version 6 -D SWIFT_PACKAGE -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift "$accessor" \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
sources=(Snaprivo/**/*.swift)
sources=("${(@)sources:#Snaprivo/App/SnagForgeApp.swift}")
xcrun swiftc -target "$(uname -m)-apple-macos26.0" -swift-version 6 -parse-as-library -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" "${sources[@]}" "$validation_dir/EnglishApp.swift" \
  Tests/Fixtures/EnglishUIFixture.swift Tests/Fixtures/SyntheticVideo.swift -o "$fixture_app/Contents/MacOS/$fixture_name"
print "$fixture_app"
