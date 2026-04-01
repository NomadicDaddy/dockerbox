#!/usr/bin/env bash
set -euo pipefail

# Install git hooks for DockerBox.
# Run from repo root: bash scripts/setup-hooks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/.git/hooks"

if [[ ! -d "${HOOKS_DIR}" ]]; then
  echo "ERROR: .git/hooks/ not found. Are you in a git repository?"
  exit 1
fi

# Install pre-commit hook
if [[ -f "${HOOKS_DIR}/pre-commit" ]] && [[ ! -L "${HOOKS_DIR}/pre-commit" ]]; then
  echo "WARNING: An existing pre-commit hook was found."
  echo "  Backing up to: ${HOOKS_DIR}/pre-commit.bak"
  mv "${HOOKS_DIR}/pre-commit" "${HOOKS_DIR}/pre-commit.bak"
fi

# Create a symlink so the hook always reflects the latest version in the repo
ln -sf "${SCRIPT_DIR}/pre-commit" "${HOOKS_DIR}/pre-commit"

echo "Pre-commit hook installed successfully."
echo "  Hook: ${HOOKS_DIR}/pre-commit -> ${SCRIPT_DIR}/pre-commit"
echo ""
echo "The hook runs on every 'git commit':"
echo "  - bash -n syntax check on all .sh files"
echo "  - prettier format check on JSON, YAML, Markdown"
echo ""
echo "To skip the hook temporarily: git commit --no-verify"
