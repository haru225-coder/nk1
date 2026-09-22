#!/usr/bin/env bash
# Cloud Agent start: bring up a virtual X display so the GUI game can be run,
# screenshotted, or recorded headlessly. Idempotent and returns promptly.
set -euo pipefail

DISPLAY_NUM="${NK1_DISPLAY:-99}"
RES="1280x720x24"

if DISPLAY=":${DISPLAY_NUM}" xdpyinfo >/dev/null 2>&1; then
	echo "Xvfb already running on :${DISPLAY_NUM}"
	exit 0
fi

echo "Starting Xvfb on :${DISPLAY_NUM} (${RES}) ..."
Xvfb ":${DISPLAY_NUM}" -screen 0 "${RES}" >/tmp/xvfb.log 2>&1 &

for _ in $(seq 1 40); do
	if DISPLAY=":${DISPLAY_NUM}" xdpyinfo >/dev/null 2>&1; then
		echo "Xvfb ready on :${DISPLAY_NUM}"
		exit 0
	fi
	sleep 0.5
done

echo "ERROR: Xvfb did not become ready on :${DISPLAY_NUM}" >&2
cat /tmp/xvfb.log >&2 || true
exit 1
