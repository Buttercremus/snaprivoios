#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/ModuleCache
CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache" \
swift test --package-path Packages/SnagForgeDomain \
  --scratch-path "$PWD/build/DomainTests" "$@"
