#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-Debug}"
DERIVED_DATA="${PROJECT_ROOT}/Build/DerivedData"

xcodebuild \
  -project "${PROJECT_ROOT}/AW Map Editor.xcodeproj" \
  -scheme "AW Map Editor" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_DIR="${DERIVED_DATA}/Build/Products/${CONFIG}/AW Map Editor.app"
echo "Built ${APP_DIR}"
