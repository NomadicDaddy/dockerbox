#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Checking *.sh syntax..."
for f in "$SCRIPT_DIR"/*.sh; do
    if [[ -f "$f" ]]; then
        echo "  Checking $(basename "$f")..."
        bash -n "$f"
    fi
done

echo "All shell scripts passed syntax check!"

if command -v shellcheck >/dev/null 2>&1; then
    echo ""
    echo "Running ShellCheck..."
    for f in "$SCRIPT_DIR"/*.sh; do
        if [[ -f "$f" ]]; then
            echo "  Checking $(basename "$f")..."
            shellcheck -x "$f"
        fi
    done
    echo "All shell scripts passed ShellCheck!"
else
    echo ""
    echo "NOTE: shellcheck not found. Install for deeper analysis:"
    echo "  apt install shellcheck  (Debian/Ubuntu)"
    echo "  brew install shellcheck (macOS)"
fi
