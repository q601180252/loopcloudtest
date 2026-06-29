#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <ipa> [watchos-min-version] [codesign-identity]" >&2
  exit 64
fi

IPA_PATH="$1"
TARGET_MINOS="${2:-9.0}"
SIGN_IDENTITY="${3:-${WATCHOS_COMPAT_CODESIGN_IDENTITY:-}}"

if [ ! -f "$IPA_PATH" ]; then
  echo "IPA not found: $IPA_PATH" >&2
  exit 66
fi

if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Distribution/ { print $2; exit }')"
fi

if [ -z "$SIGN_IDENTITY" ]; then
  echo "Apple Distribution signing identity not found" >&2
  exit 65
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/watchos-compat.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

unzip -q "$IPA_PATH" -d "$WORKDIR/unpacked"

APP_PATH="$(find "$WORKDIR/unpacked/Payload" -maxdepth 1 -type d -name "*.app" | head -n 1)"
if [ -z "$APP_PATH" ]; then
  echo "No app bundle found in IPA" >&2
  exit 65
fi

WATCH_DIR="$APP_PATH/Watch"
WATCH_APP="$(find "$WATCH_DIR" -maxdepth 1 -type d -name "*.app" | head -n 1)"
if [ -z "$WATCH_APP" ]; then
  echo "No Watch app found in IPA" >&2
  exit 65
fi

patch_binary() {
  local binary="$1"
  local info sdk ld_version output

  if ! lipo -archs "$binary" 2>/dev/null | tr ' ' '\n' | grep -qx "arm64"; then
    return 0
  fi

  info="$(xcrun vtool -show-build -arch arm64 "$binary" 2>/dev/null || true)"
  if ! printf '%s\n' "$info" | grep -q "platform WATCHOS"; then
    return 0
  fi

  sdk="$(printf '%s\n' "$info" | awk '$1 == "sdk" { print $2; exit }')"
  ld_version="$(printf '%s\n' "$info" | awk '$1 == "tool" && $2 == "LD" { getline; if ($1 == "version") print $2; exit }')"

  if [ -z "$sdk" ]; then
    echo "Cannot read watchOS SDK version from $binary" >&2
    exit 65
  fi

  output="$WORKDIR/$(basename "$binary").patched"
  if [ -n "$ld_version" ]; then
    xcrun vtool -arch arm64 \
      -set-build-version watchos "$TARGET_MINOS" "$sdk" \
      -tool ld "$ld_version" \
      -replace \
      -output "$output" \
      "$binary" >/dev/null
  else
    xcrun vtool -arch arm64 \
      -set-build-version watchos "$TARGET_MINOS" "$sdk" \
      -replace \
      -output "$output" \
      "$binary" >/dev/null
  fi

  mv "$output" "$binary"
  chmod 755 "$binary"
  echo "Patched arm64 watchOS min version: $binary -> $TARGET_MINOS"
}

while IFS= read -r bundle; do
  executable="$(plutil -extract CFBundleExecutable raw -o - "$bundle/Info.plist" 2>/dev/null || true)"
  if [ -n "$executable" ] && [ -f "$bundle/$executable" ]; then
    patch_binary "$bundle/$executable"
  fi
done < <(find "$WATCH_DIR" \( -name "*.app" -o -name "*.appex" -o -name "*.framework" \) -type d | sort)

while IFS= read -r framework; do
  codesign --force --sign "$SIGN_IDENTITY" --preserve-metadata=identifier,entitlements,flags "$framework" >/dev/null
done < <(find "$WATCH_APP" -path "*/Frameworks/*.framework" -type d | sort)

while IFS= read -r appex; do
  codesign --force --sign "$SIGN_IDENTITY" --preserve-metadata=identifier,entitlements,flags "$appex" >/dev/null
done < <(find "$WATCH_APP" -name "*.appex" -type d | sort)

codesign --force --sign "$SIGN_IDENTITY" --preserve-metadata=identifier,entitlements,flags "$WATCH_APP" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" --preserve-metadata=identifier,entitlements,flags "$APP_PATH" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null

rm -f "$IPA_PATH"
(cd "$WORKDIR/unpacked" && zip -qry "$IPA_PATH" Payload)

echo "Repacked IPA: $IPA_PATH"
