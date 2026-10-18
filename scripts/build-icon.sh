#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source_icon="$PWD/design/app-icon/AppIcon-source-v2.png"
icon_set="$PWD/Snaprivo/Resources/Assets.xcassets/AppIcon.appiconset"
for pixels in 16 32 64 128 256 512 1024; do
  sips -z "$pixels" "$pixels" "$source_icon" --out "$icon_set/icon-$pixels.png" >/dev/null
done
