#!/usr/bin/env bash
set -euo pipefail
SOURCE="$(dirname "$(dirname "$(realpath "$0")")")"
RUNTIME="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
for directory in Commons Ui services; do
  ln -s "$RUNTIME/$directory" "$CHECK/$directory"
done
for file in Panel.qml FlightMap.qml MapMath.js flight_backend.py; do
  ln -s "$SOURCE/$file" "$CHECK/$file"
done
cp "$SOURCE/tests/shell.qml" "$CHECK/shell.qml"
python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import flight_backend; flight_backend._behavior_check()' "$SOURCE"
quickshell --no-color -p "$CHECK/shell.qml" 2>&1 | tee "$CHECK/result.log"
python3 -c 'import pathlib, sys; assert "PASS: fresh install stays idle" in pathlib.Path(sys.argv[1]).read_text(), "Selection check failed"' "$CHECK/result.log"
