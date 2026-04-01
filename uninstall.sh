#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

# Defaults
REMOVE_DOCKER="false"
REMOVE_DATA="false"

for arg in "$@"; do
  case "${arg}" in
    --remove-docker) REMOVE_DOCKER="true" ;;
    --remove-data) REMOVE_DATA="true" ;;
    --help)
      cat <<'HELP'
Usage: sudo bash uninstall.sh [OPTIONS]

Stops the DockerBox stack and removes generated configuration files.
Optionally removes Docker Engine and/or the DOCKER_ROOT data directory.

Options:
  --help              Show this help message and exit
  --remove-docker     Also uninstall Docker Engine
  --remove-data       Also remove the entire DOCKER_ROOT directory

WARNING: --remove-data deletes all container data, volumes, and backups.
         --remove-docker removes Docker Engine from the system.
         Both operations are irreversible.

Configuration:
  Reads config.env from the script directory. Required variables:
    DOCKER_ROOT         Docker data root (default: /opt/docker)

Examples:
  # Remove generated configs only (safest)
  sudo bash uninstall.sh

  # Remove configs and Docker Engine
  sudo bash uninstall.sh --remove-docker

  # Full teardown: configs, data, and Docker
  sudo bash uninstall.sh --remove-docker --remove-data
HELP
      exit 0
      ;;
    *) die "Unknown argument: ${arg}. Use --help for usage." ;;
  esac
done

source_config

# Apply default guards for config variables
DOCKER_ROOT="${DOCKER_ROOT:-/opt/docker}"

confirm() {
  local prompt="$1"
  local response
  read -r -p "${prompt} [y/N]: " response
  case "${response,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

stop_stack() {
  local compose_file="${DOCKER_ROOT}/compose/core/compose.yaml"
  if [[ -f "${compose_file}" ]]; then
    log_info "Stopping Docker Compose stack"
    docker compose -f "${compose_file}" down || true
  else
    log_info "No compose.yaml found, skipping stack stop"
  fi
}

remove_configs() {
  log_info "Removing generated configuration files"

  local items=(
    "${DOCKER_ROOT}/appdata/caddy/Caddyfile"
    "${DOCKER_ROOT}/appdata/homepage/settings.yaml"
    "${DOCKER_ROOT}/appdata/homepage/widgets.yaml"
    "${DOCKER_ROOT}/appdata/homepage/services.yaml"
    "${DOCKER_ROOT}/appdata/homepage/bookmarks.yaml"
    "${DOCKER_ROOT}/compose/core/compose.yaml"
    "${DOCKER_ROOT}/scripts/backup-docker.sh"
    "${DOCKER_ROOT}/scripts/backup-docker-live.sh"
  )

  for item in "${items[@]}"; do
    if [[ -f "${item}" ]]; then
      rm -f "${item}"
    fi
  done

  # Remove empty directories left behind
  for dir in "${DOCKER_ROOT}/compose/core" "${DOCKER_ROOT}/compose"; do
    if [[ -d "${dir}" ]] && [[ -z "$(ls -A "${dir}" 2>/dev/null)" ]]; then
      rmdir "${dir}" 2>/dev/null || true
    fi
  done

  log_info "Configuration files removed"
}

remove_data() {
  if [[ "${REMOVE_DATA}" != "true" ]]; then
    return
  fi

  log_warn "--remove-data specified: this will delete ALL data under ${DOCKER_ROOT}"
  log_warn "This includes container data, volumes, and backups."

  if ! confirm "Remove ${DOCKER_ROOT} entirely?"; then
    log_info "Data removal cancelled by user"
    REMOVE_DATA="false"
    return
  fi

  log_info "Removing ${DOCKER_ROOT}"
  rm -rf "${DOCKER_ROOT}"
  log_info "Data directory removed"
}

remove_docker() {
  if [[ "${REMOVE_DOCKER}" != "true" ]]; then
    return
  fi

  log_warn "--remove-docker specified: this will uninstall Docker Engine"

  if ! confirm "Uninstall Docker Engine?"; then
    log_info "Docker removal cancelled by user"
    return
  fi

  log_info "Removing Docker Engine"
  apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
  apt autoremove -y 2>/dev/null || true
  rm -rf /etc/apt/sources.list.d/docker.list
  rm -rf /etc/apt/keyrings/docker.gpg
  rm -rf /etc/docker
  log_info "Docker Engine removed"
}

print_summary() {
  cat <<SUMMARY

========================================
Uninstall complete
========================================

Removed:
  - Docker Compose stack (stopped)
  - Generated configuration files

SUMMARY

  if [[ "${REMOVE_DATA}" == "true" ]]; then
    echo "  - DOCKER_ROOT data directory (${DOCKER_ROOT})"
    echo ""
  fi

  if [[ "${REMOVE_DOCKER}" == "true" ]]; then
    echo "  - Docker Engine"
    echo ""
  fi

  echo "To reinstall DockerBox:"
  echo "  sudo bash install.sh"
  echo ""
}

main() {
  require_root

  log_warn "This will stop the DockerBox stack and remove generated configs."
  if ! confirm "Continue with uninstall?"; then
    log_info "Uninstall cancelled"
    exit 0
  fi

  stop_stack
  remove_configs
  remove_data
  remove_docker
  print_summary
}

main "$@"
