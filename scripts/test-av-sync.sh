#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build-av-sync-fixture.sh
python3 Tests/AVSyncAnalysisChecks.py
