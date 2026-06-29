#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <ipa> [max-watchos-min-version]" >&2
  exit 64
fi

IPA_PATH="$1"
MAX_MINOS="${2:-11.6}"

if [ ! -f "$IPA_PATH" ]; then
  echo "IPA not found: $IPA_PATH" >&2
  exit 66
fi

version_gt() {
  awk -v left="$1" -v right="$2" '
    BEGIN {
      split(left, l, ".")
      split(right, r, ".")
      for (i = 1; i <= 4; i++) {
        lv = (l[i] == "" ? 0 : l[i]) + 0
        rv = (r[i] == "" ? 0 : r[i]) + 0
        if (lv > rv) exit 0
        if (lv < rv) exit 1
      }
      exit 1
    }
  '
}

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/watchos-verify.XXXXXX")"
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

WATCH_EXTENSION="$(find "$WATCH_APP/PlugIns" -maxdepth 1 -type d -name "*.appex" | head -n 1)"
if [ -z "$WATCH_EXTENSION" ]; then
  echo "No Watch extension found in IPA" >&2
  exit 65
fi

failures=0

WATCHKIT_SUPPORT="$WORKDIR/unpacked/WatchKitSupport2"
if [ ! -d "$WATCHKIT_SUPPORT" ]; then
  echo "WatchKitSupport2 folder missing from IPA" >&2
  failures=$((failures + 1))
elif ! find "$WATCHKIT_SUPPORT" -mindepth 1 -print -quit | grep -q .; then
  echo "WatchKitSupport2 folder is empty in IPA" >&2
  failures=$((failures + 1))
fi

WATCHKIT_SUPPORT_WK="$WATCHKIT_SUPPORT/WK"
WATCH_STUB_WK="$WATCH_APP/_WatchKitStub/WK"
if [ -f "$WATCHKIT_SUPPORT_WK" ] && [ -f "$WATCH_STUB_WK" ]; then
  support_hash="$(shasum -a 256 "$WATCHKIT_SUPPORT_WK" | awk '{ print $1 }')"
  stub_hash="$(shasum -a 256 "$WATCH_STUB_WK" | awk '{ print $1 }')"
  if [ "$support_hash" != "$stub_hash" ]; then
    echo "WatchKitSupport2/WK does not match Watch app _WatchKitStub/WK" >&2
    failures=$((failures + 1))
  fi
else
  echo "WatchKit WK file missing from WatchKitSupport2 or Watch app stub" >&2
  failures=$((failures + 1))
fi

check_binary() {
  local binary="$1"
  local arch info minos

  for arch in arm64_32 arm64; do
    if ! lipo -archs "$binary" 2>/dev/null | tr ' ' '\n' | grep -qx "$arch"; then
      continue
    fi

    info="$(xcrun vtool -show-build -arch "$arch" "$binary" 2>/dev/null || true)"
    if ! printf '%s\n' "$info" | grep -q "platform WATCHOS"; then
      info="$(otool -l -arch "$arch" "$binary" 2>/dev/null || true)"
      minos="$(printf '%s\n' "$info" | awk '$1 == "version" { print $2; exit }')"
    else
      minos="$(printf '%s\n' "$info" | awk '$1 == "minos" { print $2; exit }')"
    fi

    if [ -n "$minos" ] && version_gt "$minos" "$MAX_MINOS"; then
      echo "Incompatible watchOS minimum: $binary [$arch] minos=$minos > $MAX_MINOS" >&2
      failures=$((failures + 1))
    fi
  done
}

while IFS= read -r bundle; do
  if [ "$bundle" = "$WATCH_APP" ]; then
    continue
  fi

  executable="$(plutil -extract CFBundleExecutable raw -o - "$bundle/Info.plist" 2>/dev/null || true)"
  if [ -n "$executable" ] && [ -f "$bundle/$executable" ]; then
    check_binary "$bundle/$executable"
  fi
done < <(find "$WATCH_DIR" \( -name "*.app" -o -name "*.appex" -o -name "*.framework" \) -type d | sort)

codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Watch compatibility verified for $IPA_PATH"
