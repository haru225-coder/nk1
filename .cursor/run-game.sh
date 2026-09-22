#!/usr/bin/env bash
# Convenience launcher for the GUI game inside the Cloud Agent VM.
# Uses the Xvfb display from start.sh, the software OpenGL renderer
# (no GPU in the VM), and the dummy audio driver (no sound card).
#
# Usage:
#   bash .cursor/run-game.sh            # run until stopped
#   bash .cursor/run-game.sh --quit-after 8   # (any extra args forwarded to Godot)
set -euo pipefail

DISPLAY_NUM="${NK1_DISPLAY:-99}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! DISPLAY=":${DISPLAY_NUM}" xdpyinfo >/dev/null 2>&1; then
	echo "Display :${DISPLAY_NUM} not up — starting it via start.sh"
	bash "${ROOT}/.cursor/start.sh"
fi

exec env DISPLAY=":${DISPLAY_NUM}" LIBGL_ALWAYS_SOFTWARE=1 \
	godot --path "${ROOT}" \
	--rendering-method gl_compatibility \
	--rendering-driver opengl3 \
	--audio-driver Dummy \
	--resolution 1280x720 \
	"$@"
