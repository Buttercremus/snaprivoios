#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
validation_dir="$PWD/build/GuideWorkflowUI"
derived="${SNAPRIVO_QA_DERIVED_DATA:-$PWD/build/GuideWorkflowBuild}"
source_app="$derived/Build/Products/Debug/Snaprivo.app"
fixture_app="$validation_dir/SnaprivoGuideQA.app"
mkdir -p "$fixture_app/Contents/MacOS" "$fixture_app/Contents/Resources" build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
cp -R "$source_app/Contents/Resources/de.lproj" "$source_app/Contents/Resources/en.lproj" \
  "$source_app/Contents/Resources/SnagForgeDomain_SnagForgeDomain.bundle" "$fixture_app/Contents/Resources/"
python3 - "$validation_dir" "$fixture_app" <<'PY'
import plistlib, sys
from pathlib import Path
validation, app = map(Path, sys.argv[1:])
source = Path('Snaprivo/App/SnagForgeApp.swift').read_text().replace('@State private var workspace = WorkspaceModel()', '@State private var workspace = GuideWorkflowFixture.makeWorkspace()')
source = source.replace('WorkspaceView(workspace: workspace)', 'GuideWorkflowFixture.content(workspace: workspace)')
source = source.replace('.defaultSize(width: 1180, height: 780)', '.defaultSize(width: 800, height: 540)')
(validation/'GuideApp.swift').write_text(source)
info = {'CFBundleExecutable':'SnaprivoGuideQA', 'CFBundleIdentifier':'com.snaprivo.guideworkflowqa',
        'CFBundleName':'Snaprivo Guide QA', 'CFBundlePackageType':'APPL', 'CFBundleDevelopmentRegion':'de',
        'CFBundleShortVersionString':'0.1.0', 'CFBundleVersion':'2', 'LSMinimumSystemVersion':'26.0', 'NSHighResolutionCapable':True}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
accessors=("$derived"/Build/Intermediates.noindex/SnagForgeDomain.build/Debug/*/DerivedSources/resource_bundle_accessor.swift(N))
[[ ${#accessors} == 1 ]]
xcrun swiftc -target "$(uname -m)-apple-macos26.0" -swift-version 6 -D SWIFT_PACKAGE -emit-library -emit-module -module-name SnagForgeDomain \
  Packages/SnagForgeDomain/Sources/SnagForgeDomain/*.swift "$accessors[1]" \
  -emit-module-path "$validation_dir/SnagForgeDomain.swiftmodule" -o "$validation_dir/libSnagForgeDomain.dylib"
sources=(Snaprivo/**/*.swift)
sources=("${(@)sources:#Snaprivo/App/SnagForgeApp.swift}")
xcrun swiftc -target "$(uname -m)-apple-macos26.0" -swift-version 6 -D GUIDE_WORKFLOW_QA -parse-as-library -I "$validation_dir" -L "$validation_dir" -lSnagForgeDomain \
  -Xlinker -rpath -Xlinker "$validation_dir" "${sources[@]}" "$validation_dir/GuideApp.swift" Tests/Fixtures/GuideWorkflowUI.swift \
  -o "$fixture_app/Contents/MacOS/SnaprivoGuideQA"
print "$fixture_app"
