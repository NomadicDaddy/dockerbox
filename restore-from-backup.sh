#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

source_config

# Apply default guards for config variables
HOST_IP="${HOST_IP:-}"
PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}"
HOMEPAGE_DOMAIN="${HOMEPAGE_DOMAIN:-}"
DOCKER_ROOT="${DOCKER_ROOT:-/opt/docker}"

BACKUP_ARCHIVE="${1:-}"

# Check for --help
if [[ "${BACKUP_ARCHIVE}" == "--help" ]]; then
  cat <<'HELP'
Usage: sudo bash restore-from-backup.sh /path/to/backup.tar.gz

Restores DOCKER_ROOT from a tar.gz backup archive and starts the
Docker Compose stack.

Arguments:
  /path/to/backup.tar.gz   Path to the backup archive to restore

Options:
  --help                   Show this help message and exit

Configuration:
  Reads config.env from the script directory. Required variables:
    HOST_IP             Host IP address (for summary output)
    PORTAINER_DOMAIN    Portainer domain name
    HOMEPAGE_DOMAIN     Homepage dashboard domain name
    DOCKER_ROOT         Docker data root (default: /opt/docker)

The script will:
  1. Verify the backup archive exists
  2. Check SHA-256 checksum if .sha256 file is present
  3. Stop the running Docker Compose stack
  4. Extract the archive to restore DOCKER_ROOT
  5. Start the restored Docker Compose stack

Examples:
  sudo bash restore-from-backup.sh /opt/docker/shared/backups/host_backup.tar.gz
HELP
  exit 0
fi

check_args() {
  if [[ -z "${BACKUP_ARCHIVE}" ]]; then
    die "Usage: sudo bash $0 /path/to/backup.tar.gz"
  fi

  if [[ ! -f "${BACKUP_ARCHIVE}" ]]; then
    die "Backup archive not found: ${BACKUP_ARCHIVE}"
  fi
}

verify_checksum() {
  local checksum_file="${BACKUP_ARCHIVE}.sha256"

  if [[ -f "${checksum_file}" ]]; then
    log_info "Verifying SHA-256 checksum"
    if ! sha256sum -c "${checksum_file}" >/dev/null 2>&1; then
      die "SHA-256 checksum verification failed. The backup archive may be corrupted: ${BACKUP_ARCHIVE}"
    fi
    log_info "Checksum verified successfully"
  else
    log_warn "No .sha256 checksum file found for ${BACKUP_ARCHIVE}. Skipping integrity verification."
  fi
}

stop_stack() {
  local compose_file="${DOCKER_ROOT}/compose/core/compose.yaml"
  if [[ -f "${compose_file}" ]]; then
    log_info "Stopping existing stack before restore"
    docker compose -f "${compose_file}" stop || true
  fi
}

restore_archive() {
  log_info "Restoring archive ${BACKUP_ARCHIVE}"
  mkdir -p "$(dirname "${DOCKER_ROOT}")"
  tar -xzf "${BACKUP_ARCHIVE}" -C "$(dirname "${DOCKER_ROOT}")"
}

start_stack() {
  if [[ ! -f "${DOCKER_ROOT}/compose/core/compose.yaml" ]]; then
    die "compose.yaml not found after restore."
  fi

  log_info "Starting restored stack"
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
  stop_stack
  verify_checksum
  restore_archive
  start_stack
  print_summary
}

main "$@"
