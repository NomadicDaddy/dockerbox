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
STACK_WAS_STOPPED="false"
ROLLBACK_ROOT=""

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
  4. Replace DOCKER_ROOT with the archive contents
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
  local expected_hash actual_hash

  if [[ -f "${checksum_file}" ]]; then
    log_info "Verifying SHA-256 checksum"
    expected_hash="$(awk '{print $1}' "${checksum_file}")"
    if [[ -z "${expected_hash}" ]]; then
      die "SHA-256 checksum file is empty or invalid: ${checksum_file}"
    fi

    actual_hash="$(sha256sum "${BACKUP_ARCHIVE}" | awk '{print $1}')"
    if [[ "${expected_hash}" != "${actual_hash}" ]]; then
      die "SHA-256 checksum verification failed. The backup archive may be corrupted: ${BACKUP_ARCHIVE}"
    fi
    log_info "Checksum verified successfully"
  else
    log_warn "No .sha256 checksum file found for ${BACKUP_ARCHIVE}. Skipping integrity verification."
  fi
}

rollback_restore() {
  if [[ -n "${ROLLBACK_ROOT}" && -d "${ROLLBACK_ROOT}" ]]; then
    if [[ -d "${DOCKER_ROOT}" ]]; then
      rm -rf "${DOCKER_ROOT}"
    fi

    log_warn "Restore failed. Restoring previous DOCKER_ROOT from ${ROLLBACK_ROOT}"
    mv "${ROLLBACK_ROOT}" "${DOCKER_ROOT}"
  fi

  if [[ "${STACK_WAS_STOPPED}" == "true" && -f "${DOCKER_ROOT}/compose/core/compose.yaml" ]]; then
    log_warn "Restore did not complete. Restarting original stack."
    docker compose -f "${DOCKER_ROOT}/compose/core/compose.yaml" up -d || true
  fi
}

stop_stack() {
  local compose_file="${DOCKER_ROOT}/compose/core/compose.yaml"
  if [[ -f "${compose_file}" ]]; then
    log_info "Stopping existing stack before restore"
    docker compose -f "${compose_file}" stop || true
    STACK_WAS_STOPPED="true"
  fi
}

restore_archive() {
  log_info "Restoring archive ${BACKUP_ARCHIVE}"
  mkdir -p "$(dirname "${DOCKER_ROOT}")"

  if [[ -d "${DOCKER_ROOT}" ]]; then
    ROLLBACK_ROOT="${DOCKER_ROOT}.pre-restore.$(date +%Y%m%d%H%M%S)"
    mv "${DOCKER_ROOT}" "${ROLLBACK_ROOT}"
  fi

  tar -xzf "${BACKUP_ARCHIVE}" -C "$(dirname "${DOCKER_ROOT}")"

  [[ -d "${DOCKER_ROOT}" ]] || die "Restore archive did not recreate ${DOCKER_ROOT}."
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
  trap rollback_restore ERR
  verify_checksum
  stop_stack
  restore_archive
  start_stack

  if [[ -n "${ROLLBACK_ROOT}" && -d "${ROLLBACK_ROOT}" ]]; then
    rm -rf "${ROLLBACK_ROOT}"
    ROLLBACK_ROOT=""
  fi

  trap - ERR
  print_summary
}

main "$@"
