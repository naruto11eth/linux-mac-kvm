#!/bin/bash
# Builds display-detach into ./bin using the system Swift toolchain.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p bin
swiftc -O -framework CoreGraphics -framework AppKit ./*.swift -o bin/display-detach
echo "built bin/display-detach"
