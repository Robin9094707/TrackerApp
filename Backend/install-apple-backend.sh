#!/usr/bin/env bash
set -euo pipefail
BACKEND_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TRACKER_PYTHON="${TRACKER_PYTHON:-python3}"
"$TRACKER_PYTHON" -c 'import sys; assert sys.version_info >= (3, 11), "Python 3.11+ erforderlich"'
# Download/extract before changing packages. Existing data and credentials are untouched.
"$TRACKER_PYTHON" "$BACKEND_DIR/setup_apple_adi.py"
"$TRACKER_PYTHON" -m pip install --upgrade -r "$BACKEND_DIR/requirements.txt"
"$TRACKER_PYTHON" -m pip check
"$TRACKER_PYTHON" -m py_compile "$BACKEND_DIR/tracker_backend.py"
printf '%s\n' 'Fertig. Backend mit demselben Python neu starten, dann Apple in der App erneut anmelden und 2FA bestätigen.'
