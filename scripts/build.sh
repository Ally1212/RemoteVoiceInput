#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
OUTPUT_DIR="${RVI_OUTPUT_DIR:-$PWD/dist}"
APP="$OUTPUT_DIR/RemoteVoiceInput.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/RemoteVoiceInput "$APP/Contents/MacOS/RemoteVoiceInput"
SIGN_IDENTITY="${RVI_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2; exit}')}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  printf '%s\n' "Warning: no development identity found; ad-hoc updates may require authorization again." >&2
fi
codesign --force --sign "$SIGN_IDENTITY" --identifier local.lizzer.RemoteVoiceInput "$APP"
codesign --verify --deep --strict "$APP"
