#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Check for --help
for arg in "$@"; do
  case "${arg}" in
    --help)
      cat <<'HELP'
Usage: bash init.sh [OPTIONS]

Local development convenience script. Creates config.env from the template
(if missing), prompts the user to review it, then runs bootstrap and
write-configs in sequence.

Options:
  --help              Show this help message and exit

This script will:
  1. Copy config.env.example to config.env if config.env doesn't exist
  2. Prompt you to review config.env before continuing
  3. Run bootstrap-host.sh (requires sudo)
  4. Run tailscale up if INSTALL_TAILSCALE is true
  5. Run write-configs.sh (requires sudo)

Examples:
  bash init.sh
  sudo bash init.sh
HELP
      exit 0
      ;;
  esac
done

if [[ ! -f config.env ]] && [[ -f config.env.example ]]; then
  cp config.env.example config.env
  echo "Created config.env from config.env.example."
fi

echo ""
echo "Review config.env before continuing."
echo "Edit it in another terminal if needed, then press Enter."
read -r -p "Press Enter to continue (or Ctrl-C to abort)..."

sudo bash bootstrap-host.sh

# shellcheck disable=SC1091
source config.env

if [[ "${INSTALL_TAILSCALE:-}" == "true" ]]; then
  sudo tailscale up
fi

sudo bash write-configs.sh
