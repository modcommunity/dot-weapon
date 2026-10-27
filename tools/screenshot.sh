#!/usr/bin/env bash
# Render the tracer demo to a PNG under Xvfb: heavy -- tools/screenshot.sh <out.png>
set -uo pipefail
cd "$(dirname "$0")/.."
command -v Xvfb >/dev/null || { echo "Xvfb not installed" >&2; exit 3; }
[ $# -ge 1 ] || { echo "usage: $0 out.png" >&2; exit 2; }
OUT="$(realpath -m "$1")"
mkdir -p "$(dirname "$OUT")"
godot --headless --path . --import >/dev/null 2>&1
disp=$((90 + RANDOM % 8)); export DISPLAY=":$disp" LIBGL_ALWAYS_SOFTWARE=1
Xvfb ":$disp" -screen 0 1280x720x24 >/dev/null 2>&1 &
xpid=$!
sleep 2
timeout 120 godot --path . --resolution 1280x720 --rendering-method gl_compatibility --rendering-driver opengl3 res://examples/tracer_demo.tscn -- --shot "$OUT"
rc=$?
kill $xpid 2>/dev/null
exit $rc
