#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for --help
for arg in "$@"; do
  case "${arg}" in
    --help)
      cat <<'HELP'
Usage: bash lint.sh [OPTIONS]

Validates all shell scripts in the project using bash -n syntax checking.
Also runs ShellCheck if available.

Options:
  --help              Show this help message and exit

This script checks:
  - All .sh files in the project root
  - All .sh files in the lib/ directory
  - All .sh files in the scripts/ directory
  - ShellCheck static analysis (if shellcheck is installed)

Examples:
  bash lint.sh
HELP
      exit 0
      ;;
  esac
done

echo "Checking *.sh syntax..."
for f in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh "$SCRIPT_DIR"/scripts/*.sh; do
    if [[ -f "$f" ]]; then
        echo "  Checking $(basename "$f")..."
        bash -n "$f"
    fi
done

echo "All shell scripts passed syntax check!"

if command -v shellcheck >/dev/null 2>&1; then
    echo ""
    echo "Running ShellCheck..."
    for f in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh "$SCRIPT_DIR"/scripts/*.sh; do
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
