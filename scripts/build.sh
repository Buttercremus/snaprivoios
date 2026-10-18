#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project Snaprivo.xcodeproj -scheme Snaprivo \
  -configuration Debug -destination 'platform=macOS' \
  build "$@"
