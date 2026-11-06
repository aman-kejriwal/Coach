#!/bin/bash
# Builds Coach.app with swiftc directly (works with just the Command Line Tools, no Xcode needed).
#   scripts/build.sh            → build/Coach.app
#   scripts/build.sh --test     → also run the CoachCore unit tests
#   scripts/build.sh --install  → also copy to /Applications and launch it
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=build
OBJ=$BUILD/obj
APP=$BUILD/Coach.app
TARGET="$(uname -m)-apple-macos14.0"
CLT_DEV=/Library/Developer/CommandLineTools/Library/Developer
rm -rf "$OBJ" && mkdir -p "$OBJ"

echo "→ Compiling CoachCore"
swiftc -O -target "$TARGET" -parse-as-library -module-name CoachCore -enable-testing \
  -emit-library -static -emit-module -emit-module-path "$OBJ/CoachCore.swiftmodule" \
  -o "$OBJ/libCoachCore.a" Sources/CoachCore/*.swift

if [[ " $* " == *" --test "* ]]; then
  echo "→ Running tests"
  cat > "$OBJ/TestMain.swift" <<'EOF'
import Testing
@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }
EOF
  swiftc -target "$TARGET" -parse-as-library -I "$OBJ" -L "$OBJ" -lCoachCore \
    -F "$CLT_DEV/Frameworks" -framework Testing -Xlinker -rpath -Xlinker "$CLT_DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT_DEV/usr/lib" \
    -plugin-path /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
    Tests/CoachCoreTests/*.swift "$OBJ/TestMain.swift" -o "$OBJ/CoachTests"
  "$OBJ/CoachTests"
fi

echo "→ Compiling Coach"
swiftc -O -target "$TARGET" -parse-as-library -module-name Coach -I "$OBJ" -L "$OBJ" -lCoachCore \
  Sources/Coach/*.swift Sources/Coach/Views/*.swift -o "$OBJ/Coach"

echo "→ Bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OBJ/Coach" "$APP/Contents/MacOS/Coach"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "✓ Built $PWD/$APP"

if [[ " $* " == *" --install "* ]]; then
  pkill -x Coach 2>/dev/null || true
  rm -rf /Applications/Coach.app
  cp -R "$APP" /Applications/
  touch /Applications/Coach.app  # nudge Finder/Dock to pick up the new icon
  open /Applications/Coach.app
  echo "✓ Installed to /Applications/Coach.app"
fi
