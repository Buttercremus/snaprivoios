#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project Snaprivo.xcodeproj -scheme SnaprivoStoreTests -destination 'platform=macOS' \
  -derivedDataPath "$PWD/build/StoreKitXcodeTests" test "$@"
