#!/bin/zsh
# Build the app (Release, arm64, ad-hoc signed) and optionally install it.
#
# usage: Scripts/build.sh            # build into ./build/mac-stats.app
#        Scripts/build.sh --install  # build, then replace /Applications/mac-stats.app
#
# Requires Xcode 27+ and xcodegen (brew install xcodegen).
# DERIVED_DATA=<dir> overrides the build cache location (default build/DerivedData).

set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen"; exit 1; }

dd="${DERIVED_DATA:-build/DerivedData}"
mkdir -p build
xcodegen generate --quiet
# Fail loudly: the old `| grep ... || true` swallowed xcodebuild's exit code and shipped a stale app.
if ! xcodebuild -project mac-stats.xcodeproj -scheme mac-stats -configuration Release \
  -derivedDataPath "$dd" build > build/xcodebuild.log 2>&1; then
  grep -E "error:" build/xcodebuild.log | sort -u || true
  echo "build failed, full log: build/xcodebuild.log"
  exit 1
fi
grep -E "warning: .*\.swift" build/xcodebuild.log | sort -u || true

app="$dd/Build/Products/Release/mac-stats.app"
[[ -d "$app" ]] || { echo "build failed: $app missing"; exit 1; }
rm -rf build/mac-stats.app
cp -R "$app" build/mac-stats.app
echo "built build/mac-stats.app ($(du -sh build/mac-stats.app | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
  if pgrep -x mac-stats >/dev/null; then
    echo "quitting running mac-stats..."
    osascript -e 'tell application "mac-stats" to quit' 2>/dev/null || pkill -x mac-stats || true
    sleep 2
  fi
  rm -rf /Applications/mac-stats.app
  cp -R build/mac-stats.app /Applications/mac-stats.app
  echo "installed /Applications/mac-stats.app"
  open /Applications/mac-stats.app
fi
