#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}

export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swiftpm-module-cache"
SWIFTPM_ARGS=(
  --disable-sandbox
  --cache-path "$PROJECT_DIR/.build/swiftpm-cache"
  --config-path "$PROJECT_DIR/.build/swiftpm-config"
  --security-path "$PROJECT_DIR/.build/swiftpm-security"
)

swift build --package-path "$PROJECT_DIR" -c release "${SWIFTPM_ARGS[@]}"
BIN_DIR=$(swift build --package-path "$PROJECT_DIR" -c release --show-bin-path "${SWIFTPM_ARGS[@]}")
APP_DIR="$PROJECT_DIR/.build/TermiNap.app"

/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/bin/cp "$BIN_DIR/TermiNap" "$APP_DIR/Contents/MacOS/TermiNap"
/bin/cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/chmod 755 "$APP_DIR/Contents/MacOS/TermiNap"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
