#!/usr/bin/env bash
# Cloud Agent install: bootstrap the Godot 4.6 toolchain + validate the project.
# Idempotent: safe to run repeatedly. No process is left running here (see start.sh).
set -euo pipefail

GODOT_VERSION="4.6.3-stable"
GODOT_TAG="4.6.3"            # substring used for the version check
GODOT_BIN="/usr/local/bin/godot"
PKG_NAME="Godot_v${GODOT_VERSION}_linux.x86_64"
DOWNLOAD_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${PKG_NAME}.zip"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install_godot() {
	if [ -x "${GODOT_BIN}" ] && "${GODOT_BIN}" --version 2>/dev/null | grep -q "${GODOT_TAG}"; then
		echo "Godot already present: $("${GODOT_BIN}" --version)"
		return
	fi
	echo "Downloading Godot ${GODOT_VERSION} ..."
	local tmp
	tmp="$(mktemp -d)"
	curl -fsSL -o "${tmp}/godot.zip" "${DOWNLOAD_URL}"
	unzip -o -q "${tmp}/godot.zip" -d "${tmp}"
	sudo mv "${tmp}/${PKG_NAME}" "${GODOT_BIN}"
	sudo chmod +x "${GODOT_BIN}"
	rm -rf "${tmp}"
	echo "Installed: $("${GODOT_BIN}" --version)"
}

install_godot

# Import assets/scenes so the project is ready to open/run headlessly.
# First import also generates the local .godot/ cache.
echo "Importing Godot project (headless) ..."
godot --headless --path "${ROOT}" --import

# Static validation suite (pure Python stdlib, no third-party deps).
echo "Running static validators ..."
python3 "${ROOT}/tools/check_symbols.py"
python3 "${ROOT}/tools/verify_economy.py"
python3 "${ROOT}/tools/simulate_run.py"

echo "install.sh: environment ready."
