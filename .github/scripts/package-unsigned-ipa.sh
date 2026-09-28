#!/bin/bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <App.app> <output.ipa>" >&2
  exit 64
fi

APP_PATH="$1"
OUTPUT_IPA="$2"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: app bundle not found: $APP_PATH" >&2
  exit 1
fi

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
mkdir -p "$(dirname "$OUTPUT_IPA")"
OUTPUT_IPA="$(cd "$(dirname "$OUTPUT_IPA")" && pwd)/$(basename "$OUTPUT_IPA")"

python3 - "$APP_PATH" <<'PY'
import os
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
info_path = app / "Info.plist"
if not info_path.is_file():
    raise SystemExit(f"ERROR: Info.plist not found in {app}")

try:
    with info_path.open("rb") as source:
        info = plistlib.load(source)
except Exception as error:
    raise SystemExit(f"ERROR: cannot read {info_path}: {error}")

bundle_id = info.get("CFBundleIdentifier")
executable = info.get("CFBundleExecutable")
display_name = (
    info.get("CFBundleDisplayName")
    or info.get("CFBundleName")
    or executable
)

for key, value in {
    "app name": display_name,
    "CFBundleIdentifier": bundle_id,
    "CFBundleExecutable": executable,
}.items():
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"ERROR: {key} is missing from {info_path}")

executable_path = app / executable
if not executable_path.is_file():
    raise SystemExit(f"ERROR: executable not found: {executable_path}")
if not os.access(executable_path, os.X_OK):
    raise SystemExit(f"ERROR: executable bit is not set: {executable_path}")

print(f"Validated app: {display_name} ({bundle_id}), executable {executable}")
PY

STAGE_ROOT="$(mktemp -d "${TMPDIR:-$PWD}/package-ipa.XXXXXX")"
trap 'rm -rf "$STAGE_ROOT"' EXIT
mkdir -p "$STAGE_ROOT/Payload"

if command -v ditto >/dev/null 2>&1; then
  ditto "$APP_PATH" "$STAGE_ROOT/Payload/$(basename "$APP_PATH")"
else
  cp -R "$APP_PATH" "$STAGE_ROOT/Payload/"
fi

rm -f "$OUTPUT_IPA"
if command -v ditto >/dev/null 2>&1; then
  (
    cd "$STAGE_ROOT"
    ditto -c -k --sequesterRsrc --keepParent Payload "$OUTPUT_IPA"
  )
else
  (
    cd "$STAGE_ROOT"
    zip -qry "$OUTPUT_IPA" Payload
  )
fi

python3 - "$OUTPUT_IPA" <<'PY'
import os
import plistlib
import re
import stat
import sys
import zipfile

ipa_path = sys.argv[1]
with zipfile.ZipFile(ipa_path) as archive:
    names = archive.namelist()
    info_paths = [
        name
        for name in names
        if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)
    ]
    if len(info_paths) != 1:
        raise SystemExit(
            "ERROR: IPA must contain exactly one Payload/*.app/Info.plist; "
            f"found {info_paths}"
        )

    info_path = info_paths[0]
    try:
        info = plistlib.loads(archive.read(info_path))
    except Exception as error:
        raise SystemExit(f"ERROR: cannot read archived {info_path}: {error}")

    executable = info.get("CFBundleExecutable")
    display_name = (
        info.get("CFBundleDisplayName")
        or info.get("CFBundleName")
        or executable
    )
    bundle_id = info.get("CFBundleIdentifier")
    app_root = info_path.removesuffix("Info.plist")
    executable_path = f"{app_root}{executable}"

    for key, value in {
        "app name": display_name,
        "CFBundleIdentifier": bundle_id,
        "CFBundleExecutable": executable,
    }.items():
        if not isinstance(value, str) or not value.strip():
            raise SystemExit(f"ERROR: {key} is missing from archived {info_path}")

    try:
        executable_entry = archive.getinfo(executable_path)
    except KeyError:
        raise SystemExit(
            f"ERROR: archived executable does not match CFBundleExecutable: "
            f"{executable_path}"
        )

    mode = stat.S_IMODE(executable_entry.external_attr >> 16)
    if not mode & 0o111:
        raise SystemExit(
            f"ERROR: archived executable bit is not set: {executable_path} "
            f"({oct(mode)})"
        )

print(f"Validated IPA: {ipa_path}")
PY

echo "Created $OUTPUT_IPA"
