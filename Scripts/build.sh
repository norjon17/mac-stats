#!/bin/zsh
# Build the app (Release, arm64, ad-hoc signed) and optionally install it.
#
# usage: Scripts/build.sh            # build into ./build/Stats.app
#        Scripts/build.sh --install  # build, then replace /Applications/Stats.app
#
# Requires Xcode 27+ and xcodegen (brew install xcodegen).

set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen"; exit 1; }

xcodegen generate --quiet
xcodebuild -project Stats.xcodeproj -scheme Stats -configuration Release \
  -derivedDataPath build/DerivedData build 2>&1 | grep -E "error:|warning: .*\.swift|BUILD" || true

app="build/DerivedData/Build/Products/Release/Stats.app"
[[ -d "$app" ]] || { echo "build failed: $app missing"; exit 1; }
rm -rf build/Stats.app
cp -R "$app" build/Stats.app
echo "built build/Stats.app ($(du -sh build/Stats.app | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
  if pgrep -x Stats >/dev/null; then
    echo "quitting running Stats..."
    osascript -e 'tell application "Stats" to quit' 2>/dev/null || pkill -x Stats || true
    sleep 2
  fi
  rm -rf /Applications/Stats.app
  cp -R build/Stats.app /Applications/Stats.app
  echo "installed /Applications/Stats.app"
  open /Applications/Stats.app
fi
