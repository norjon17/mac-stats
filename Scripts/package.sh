#!/bin/zsh
# Package a built app bundle into a DMG and an installer PKG (both unsigned,
# the app itself is ad-hoc signed by Scripts/build.sh).
#
# usage: Scripts/package.sh [path/to/App.app]   # default: build/mac-stats.app
#
# Produces build/<name>-<version>.dmg and build/<name>-<version>.pkg, where
# <name> and <version> come from the bundle's Info.plist (CFBundleName,
# CFBundleShortVersionString). Uses only hdiutil / pkgbuild / productbuild.

set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-build/mac-stats.app}"
[[ -d "$app" ]] || { echo "app bundle not found: $app (run Scripts/build.sh first)"; exit 1; }
plist="$app/Contents/Info.plist"
[[ -f "$plist" ]] || { echo "missing $plist"; exit 1; }

pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
name="$(pb CFBundleName)"
version="$(pb CFBundleShortVersionString)"
bundle_id="$(pb CFBundleIdentifier)"
app_file="$(basename "$app")"
[[ -n "$name" && -n "$version" && -n "$bundle_id" ]] || { echo "Info.plist is missing CFBundleName/CFBundleShortVersionString/CFBundleIdentifier"; exit 1; }

mkdir -p build
dmg="build/$name-$version.dmg"
pkg="build/$name-$version.pkg"
tmp="$(mktemp -d -t package-"$name")"
trap 'rm -rf "$tmp"' EXIT

echo "packaging $app ($name $version, $bundle_id)"

# --- DMG -------------------------------------------------------------------
echo "creating $dmg..."
mkdir -p "$tmp/dmg"
cp -R "$app" "$tmp/dmg/$app_file"
ln -s /Applications "$tmp/dmg/Applications"
rm -f "$dmg"
hdiutil create -volname "$name" -srcfolder "$tmp/dmg" -ov -format UDZO -quiet "$dmg"
echo "verifying $dmg..."
hdiutil verify -quiet "$dmg"

# --- PKG -------------------------------------------------------------------
echo "creating $pkg..."
mkdir -p "$tmp/scripts"
cat > "$tmp/scripts/postinstall" <<POST
#!/bin/sh
# Strip the quarantine flag (the app is ad-hoc signed) and launch it.
xattr -dr com.apple.quarantine "/Applications/$app_file" 2>/dev/null || true
# Installer runs this as root; launch the app as the logged-in user instead.
console_user="\$(stat -f %Su /dev/console 2>/dev/null || true)"
if [ -n "\$console_user" ] && [ "\$console_user" != "root" ]; then
  sudo -u "\$console_user" open "/Applications/$app_file" 2>/dev/null || true
else
  open "/Applications/$app_file" 2>/dev/null || true
fi
exit 0
POST
chmod +x "$tmp/scripts/postinstall"

# Build from a root directory with an explicit component plist so the app is
# NOT relocatable. By default Installer looks up any registered copy of the
# bundle id (even one sitting in a build folder) and installs over that copy
# instead of /Applications.
mkdir -p "$tmp/root"
cp -R "$app" "$tmp/root/$app_file"
pkgbuild --analyze --root "$tmp/root" "$tmp/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$tmp/component.plist"
component="$tmp/$name-component.pkg"
pkgbuild --quiet --root "$tmp/root" --component-plist "$tmp/component.plist" \
  --install-location /Applications \
  --identifier "$bundle_id.pkg" --version "$version" \
  --scripts "$tmp/scripts" "$component"
rm -f "$pkg"
productbuild --quiet --package "$component" "$pkg"

echo "verifying $pkg..."
pkgutil --expand-full "$pkg" "$tmp/expanded"
expanded_component="$(find "$tmp/expanded" -maxdepth 1 -name '*.pkg' -type d | head -n 1)"
[[ -n "$expanded_component" ]] || { echo "pkg verification failed: no component package inside $pkg"; exit 1; }
[[ -f "$expanded_component/Payload/$app_file/Contents/Info.plist" ]] \
  || { echo "pkg verification failed: $app_file/Contents/Info.plist not in payload"; exit 1; }
grep -q "com.apple.quarantine" "$expanded_component/Scripts/postinstall" \
  || { echo "pkg verification failed: postinstall script missing"; exit 1; }
grep -q 'relocatable="false"' "$expanded_component/PackageInfo" \
  || { echo "pkg verification failed: $app_file is still marked relocatable"; exit 1; }

# --- Summary ---------------------------------------------------------------
echo
echo "built $dmg ($(du -h "$dmg" | cut -f1))"
echo "built $pkg ($(du -h "$pkg" | cut -f1))"
echo
echo "note: $app_file is ad-hoc signed (no Developer ID / notarization). On other"
echo "Macs, Gatekeeper will say it is from an unidentified developer. Fix: right-click"
echo "the app -> Open once, or run:  xattr -dr com.apple.quarantine /Applications/$app_file"
echo "The .pkg's postinstall already does the latter after installing."
