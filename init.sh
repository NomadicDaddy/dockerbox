#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

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
