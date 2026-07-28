#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
SOURCE_APP="$PROJECT_DIR/.build/TermiNap.app"
TARGET_DIR="$HOME/Applications"
TARGET_APP="$TARGET_DIR/TermiNap.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$SCRIPT_DIR/build-app.sh"
fi

/bin/mkdir -p "$TARGET_DIR"
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"
/usr/bin/codesign --verify --deep --strict "$TARGET_APP"

echo "$TARGET_APP"
