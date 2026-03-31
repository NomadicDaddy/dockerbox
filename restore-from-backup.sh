#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
CONFIG_TEMPLATE_FILE="${SCRIPT_DIR}/config.env.example"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  if [[ -f "${CONFIG_TEMPLATE_FILE}" ]]; then
    echo "ERROR: config.env not found at ${CONFIG_FILE}" >&2
    echo "Copy config.env.example to config.env and update it for this host." >&2
  else
    echo "ERROR: config.env not found at ${CONFIG_FILE}" >&2
  fi
  exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

if [[ -z "${DOCKER_ROOT:-}" ]]; then
  DOCKER_ROOT="/opt/docker"
fi

BACKUP_ARCHIVE="${1:-}"

log() {
  echo
  echo "==> $*"
}

die() {
  echo
  echo "ERROR: $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root: sudo bash $0 /path/to/backup.tar.gz"
  fi
}

check_args() {
  if [[ -z "${BACKUP_ARCHIVE}" ]]; then
    die "Usage: sudo bash $0 /path/to/backup.tar.gz"
  fi

  if [[ ! -f "${BACKUP_ARCHIVE}" ]]; then
    die "Backup archive not found: ${BACKUP_ARCHIVE}"
  fi
}

check_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed."
  docker version >/dev/null 2>&1 || die "Docker daemon is not available."
}

restore_archive() {
  log "Restoring archive ${BACKUP_ARCHIVE}"
  mkdir -p "$(dirname "${DOCKER_ROOT}")"
  tar -xzf "${BACKUP_ARCHIVE}" -C "$(dirname "${DOCKER_ROOT}")"
}

start_stack() {
  if [[ ! -f "${DOCKER_ROOT}/compose/core/compose.yaml" ]]; then
    die "compose.yaml not found after restore."
  fi

  log "Starting restored stack"
  docker compose -f "${DOCKER_ROOT}/compose/core/compose.yaml" up -d
}

print_summary() {
  cat <<SUMMARY

========================================
Restore complete
========================================

Verify:
  docker compose -f ${DOCKER_ROOT}/compose/core/compose.yaml ps

If client devices do not trust HTTPS:
  Check whether this CA was restored:
  ${DOCKER_ROOT}/appdata/caddy/data/caddy/pki/authorities/local/root.crt

If the host IP changed:
  Update local DNS or hosts file entries:
  ${HOST_IP} ${PORTAINER_DOMAIN} ${HOMEPAGE_DOMAIN}

SUMMARY
}

main() {
  require_root
  check_args
  check_docker
  restore_archive
  start_stack
  print_summary
}

main "$@"
