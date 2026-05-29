#!/usr/bin/env bash
# Thin wrapper — installs the Python deps the orchestration script
# needs into a local venv and runs it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="$HERE/.venv"

if [[ ! -d "$VENV" ]]; then
    echo "==> creating postdeploy venv at $VENV"
    python3 -m venv "$VENV"
fi
# shellcheck disable=SC1091
. "$VENV/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet \
    azure-identity \
    'azure-containerapps-sandbox==0.1.0b1'

exec python "$HERE/postdeploy.py" "$@"
