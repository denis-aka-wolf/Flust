#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "ERROR: powershell.exe was not found. Run this script from Git Bash / MinGW on Windows."
    exit 1
fi

if ! command -v cygpath >/dev/null 2>&1; then
    echo "ERROR: cygpath was not found. Use Git Bash / MinGW with cygpath installed."
    exit 1
fi

PS_SCRIPT="$(cygpath -w "$SCRIPT_DIR/setup_flust.ps1")"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT"
