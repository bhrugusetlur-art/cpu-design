#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

test -f requirements-visuals.txt
grep -Eq '^Pillow([<=>].*)?$' requirements-visuals.txt

fake_python=$(mktemp)
trap 'rm -f "$fake_python"' EXIT
printf '#!/bin/sh\nexit 1\n' >"$fake_python"
chmod +x "$fake_python"

if output=$(make -s check-visual-deps PYTHON="$fake_python" 2>&1); then
    echo "FAIL: dependency check accepted a Python without Pillow" >&2
    exit 1
fi

grep -q 'requirements-visuals.txt' <<<"$output"

echo "PASS: visual dependency setup is declared and reports the install command"
