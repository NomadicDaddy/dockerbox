#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Checking *.sh..."
for f in "$SCRIPT_DIR"/*.sh; do
    if [[ -f "$f" ]]; then
        echo "  Checking $(basename "$f")..."
        bash -n "$f"
    fi
done

echo "All shell scripts passed syntax check!"
