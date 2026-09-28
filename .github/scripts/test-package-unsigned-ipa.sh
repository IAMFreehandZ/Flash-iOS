#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGER="$SCRIPT_DIR/package-unsigned-ipa.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-$PWD}/package-ipa-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

APP="$TEST_ROOT/FlashMoE.app"
IPA="$TEST_ROOT/FlashMoE-unsigned.ipa"

mkdir -p "$APP"
python3 - "$APP/Info.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as output:
    plistlib.dump(
        {
            "CFBundleDisplayName": "Flash-MoE",
            "CFBundleExecutable": "FlashMoE",
            "CFBundleIdentifier": "com.flashmoe.ios",
            "CFBundleName": "FlashMoE",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
        },
        output,
        fmt=plistlib.FMT_BINARY,
    )
PY
printf '#!/bin/sh\nexit 0\n' > "$APP/FlashMoE"
chmod 755 "$APP/FlashMoE"

bash "$PACKAGER" "$APP" "$IPA"

python3 - "$IPA" <<'PY'
import plistlib
import stat
import sys
import zipfile

ipa_path = sys.argv[1]
info_path = "Payload/FlashMoE.app/Info.plist"
executable_path = "Payload/FlashMoE.app/FlashMoE"

with zipfile.ZipFile(ipa_path) as archive:
    names = archive.namelist()
    info_files = [
        name
        for name in names
        if name.startswith("Payload/") and name.endswith(".app/Info.plist")
    ]
    assert info_files == [info_path], info_files

    info = plistlib.loads(archive.read(info_path))
    assert info["CFBundleDisplayName"] == "Flash-MoE"
    assert info["CFBundleIdentifier"] == "com.flashmoe.ios"
    assert info["CFBundleExecutable"] == "FlashMoE"

    executable = archive.getinfo(executable_path)
    mode = executable.external_attr >> 16
    assert stat.S_IMODE(mode) & 0o111, oct(mode)
PY

BROKEN_APP="$TEST_ROOT/Broken.app"
mkdir -p "$BROKEN_APP"
if bash "$PACKAGER" "$BROKEN_APP" "$TEST_ROOT/Broken.ipa" 2>"$TEST_ROOT/broken.err"; then
  echo "ERROR: packaging an app without Info.plist succeeded" >&2
  exit 1
fi
grep -q "Info.plist" "$TEST_ROOT/broken.err"

echo "package-unsigned-ipa tests passed"
