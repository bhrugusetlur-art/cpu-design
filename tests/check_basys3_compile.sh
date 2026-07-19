#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
make -s basys3-compile

test -s build/basys3_compile
echo "PASS: Basys3 wrapper elaborates with the complete CPU"
