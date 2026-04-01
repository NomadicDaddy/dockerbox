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

# Apply default guards for config variables
HOST_IP="${HOST_IP:-}"
HOSTNAME_TO_SET="${HOSTNAME_TO_SET:-}"
PRIMARY_USER="${PRIMARY_USER:-}"
TZ="${TZ:-UTC}"
PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}"
HOMEPAGE_DOMAIN="${HOMEPAGE_DOMAIN:-}"
INSTALL_TAILSCALE="${INSTALL_TAILSCALE:-false}"
ENABLE_UFW="${ENABLE_UFW:-false}"
ENABLE_UNATTENDED_UPGRADES="${ENABLE_UNATTENDED_UPGRADES:-false}"
HARDEN_SSH="${HARDEN_SSH:-false}"
ENABLE_WATCHTOWER="${ENABLE_WATCHTOWER:-false}"
DOCKER_ROOT="${DOCKER_ROOT:-/opt/docker}"
BACKUP_RETAIN_DAYS="${BACKUP_RETAIN_DAYS:-14}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:2}"
HOMEPAGE_IMAGE="${HOMEPAGE_IMAGE:-ghcr.io/gethomepage/homepage:latest}"
WATCHTOWER_IMAGE="${WATCHTOWER_IMAGE:-containrrr/watchtower:1.7.1}"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:2}"

# Validate required config variables
missing_vars=()
if [[ -z "${HOST_IP}" ]]; then missing_vars+=("HOST_IP"); fi
if [[ -z "${PORTAINER_DOMAIN}" ]]; then missing_vars+=("PORTAINER_DOMAIN"); fi
if [[ -z "${HOMEPAGE_DOMAIN}" ]]; then missing_vars+=("HOMEPAGE_DOMAIN"); fi
if [[ -z "${DOCKER_ROOT}" ]]; then missing_vars+=("DOCKER_ROOT"); fi

if [[ ${#missing_vars[@]} -gt 0 ]]; then
  echo "ERROR: Required config variables are missing from ${CONFIG_FILE}:" >&2
  for var in "${missing_vars[@]}"; do
    echo "  - ${var}" >&2
  done
  echo "Copy config.env.example to config.env and fill in the required values." >&2
  exit 1
fi

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
    die "Please run as root: sudo bash $0"
  fi
}

check_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed."
  docker version >/dev/null 2>&1 || die "Docker daemon is not available."
}

check_directories() {
  [[ -d "${DOCKER_ROOT}" ]] || die "${DOCKER_ROOT} does not exist."
}

write_caddyfile() {
  log "Writing Caddyfile"
  cat > "${DOCKER_ROOT}/appdata/caddy/Caddyfile" <<CADDYFILE
{
  local_certs
}

(security_headers) {
  header {
    X-Content-Type-Options "nosniff"
    X-Frame-Options "SAMEORIGIN"
    Referrer-Policy "strict-origin-when-cross-origin"
    Permissions-Policy "geolocation=(), microphone=(), camera=()"
    -Server
  }
}

http://${PORTAINER_DOMAIN}, http://${HOMEPAGE_DOMAIN} {
  redir https://{host}{uri} permanent
}

https://${PORTAINER_DOMAIN} {
  import security_headers
  encode zstd gzip

  reverse_proxy portainer:9443 {
    transport http {
      tls_insecure_skip_verify
    }
  }
}

https://${HOMEPAGE_DOMAIN} {
  import security_headers
  encode zstd gzip

  reverse_proxy homepage:3000
}
CADDYFILE
}

write_homepage_files() {
  log "Writing Homepage config"

  cat > "${DOCKER_ROOT}/appdata/homepage/settings.yaml" <<'SETTINGS'
title: Docker Host
description: Core services dashboard
theme: dark
color: slate
headerStyle: clean
language: en
layout:
  Management:
    style: row
    columns: 2
  System:
    style: row
    columns: 2
SETTINGS

  cat > "${DOCKER_ROOT}/appdata/homepage/widgets.yaml" <<'WIDGETS'
- resources:
    cpu: true
    memory: true
    disk: /
    cputemp: false

- search:
    provider: duckduckgo
    target: _blank

- datetime:
    text_size: xl
    format:
      timeStyle: short
      hourCycle: h23
      dateStyle: short
WIDGETS

  cat > "${DOCKER_ROOT}/appdata/homepage/services.yaml" <<SERVICES
- Management:
    - Portainer:
        href: https://${PORTAINER_DOMAIN}
        description: Docker management UI
        icon: portainer.png
        siteMonitor: https://${PORTAINER_DOMAIN}

- System:
    - Homepage:
        href: https://${HOMEPAGE_DOMAIN}
        description: Main dashboard
        icon: homepage.png
        siteMonitor: https://${HOMEPAGE_DOMAIN}
SERVICES

  cat > "${DOCKER_ROOT}/appdata/homepage/bookmarks.yaml" <<'BOOKMARKS'
- Admin:
    - Debian Docs:
        - href: https://www.debian.org/doc/
    - Docker Docs:
        - href: https://docs.docker.com/
    - Portainer Docs:
        - href: https://docs.portainer.io/
    - Caddy Docs:
        - href: https://caddyserver.com/docs/

- Network:
    - Tailscale Admin:
        - href: https://login.tailscale.com/admin
BOOKMARKS
}

write_compose_file() {
  log "Writing compose.yaml"

  local watchtower_service=""
  local portainer_labels="      - homepage.group=Management
      - homepage.name=Portainer
      - homepage.icon=portainer.png
      - homepage.href=https://${PORTAINER_DOMAIN}
      - homepage.description=Docker management UI"
  local homepage_labels="      - homepage.group=System
      - homepage.name=Homepage
      - homepage.icon=homepage.png
      - homepage.href=https://${HOMEPAGE_DOMAIN}
      - homepage.description=Main dashboard"
  local caddy_labels='      - com.centurylinklabs.watchtower.enable=false'

  if [[ "${ENABLE_WATCHTOWER}" == "true" ]]; then
    portainer_labels="      - com.centurylinklabs.watchtower.enable=true
${portainer_labels}"
    homepage_labels="      - com.centurylinklabs.watchtower.enable=true
${homepage_labels}"

    watchtower_service=$(cat <<WATCHTOWER

  watchtower:
    image: ${WATCHTOWER_IMAGE}
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      WATCHTOWER_LABEL_ENABLE: "true"
      WATCHTOWER_POLL_INTERVAL: "21600"
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_LOG_LEVEL: "info"
      WATCHTOWER_ROLLING_RESTART: "true"
WATCHTOWER
)
  fi

  cat > "${DOCKER_ROOT}/compose/core/compose.yaml" <<COMPOSE
services:
  portainer:
    image: ${PORTAINER_IMAGE}
    container_name: portainer
    restart: unless-stopped
    expose:
      - "9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${DOCKER_ROOT}/appdata/portainer:/data
    healthcheck:
      test: ["CMD", "curl", "-fk", "https://localhost:9443/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
${portainer_labels}

  homepage:
    image: ${HOMEPAGE_IMAGE}
    container_name: homepage
    restart: unless-stopped
    expose:
      - "3000"
    volumes:
      - ${DOCKER_ROOT}/appdata/homepage:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      HOMEPAGE_ALLOWED_HOSTS: "${HOMEPAGE_DOMAIN}"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
    labels:
${homepage_labels}
${watchtower_service}  caddy:
    image: ${CADDY_IMAGE}
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${DOCKER_ROOT}/appdata/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${DOCKER_ROOT}/appdata/caddy/data:/data
      - ${DOCKER_ROOT}/appdata/caddy/config:/config
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    labels:
${caddy_labels}
COMPOSE
}

write_backup_scripts() {
  log "Writing backup scripts"

  cat > "${DOCKER_ROOT}/scripts/backup-docker.sh" <<BACKUPSAFE
#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${DOCKER_ROOT}/compose/core"
BACKUP_ROOT="${DOCKER_ROOT}/shared/backups"
TIMESTAMP="\$(date +%Y-%m-%d_%H-%M-%S)"
HOSTNAME_SHORT="\$(hostname -s)"
ARCHIVE_NAME="\${HOSTNAME_SHORT}_docker_backup_\${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="\${BACKUP_ROOT}/\${ARCHIVE_NAME}"
RETAIN_DAYS="${BACKUP_RETAIN_DAYS}"

mkdir -p "\${BACKUP_ROOT}"

stack_stopped="false"

restore_stack() {
  if [[ "\${stack_stopped}" == "true" ]]; then
    echo "[backup] Restarting stack..."
    docker compose -f "\${STACK_DIR}/compose.yaml" start || true
  fi
}

trap restore_stack EXIT

echo "[backup] Stopping stack..."
docker compose -f "\${STACK_DIR}/compose.yaml" stop || true
stack_stopped="true"

echo "[backup] Creating archive..."
tar \\
  --exclude="\${BACKUP_ROOT}" \\
  -czf "\${ARCHIVE_PATH}" \\
  -C "\$(dirname "${DOCKER_ROOT}")" "\$(basename "${DOCKER_ROOT}")"

ARCHIVE_SIZE="\$(du -sh "\${ARCHIVE_PATH}" | cut -f1)"
echo "[backup] Archive created: \${ARCHIVE_PATH} (\${ARCHIVE_SIZE})"

echo "[backup] Generating SHA-256 checksum..."
sha256sum "\${ARCHIVE_PATH}" > "\${ARCHIVE_PATH}.sha256"
echo "[backup] Checksum written: \${ARCHIVE_PATH}.sha256"

echo "[backup] Pruning archives older than \${RETAIN_DAYS} days..."
find "\${BACKUP_ROOT}" -type f -name "*.tar.gz" -mtime +\${RETAIN_DAYS} -delete
find "\${BACKUP_ROOT}" -type f -name "*.tar.gz.sha256" -mtime +\${RETAIN_DAYS} -delete

echo "[backup] Done."
BACKUPSAFE

  chmod +x "${DOCKER_ROOT}/scripts/backup-docker.sh"

  cat > "${DOCKER_ROOT}/scripts/backup-docker-live.sh" <<BACKUPLIVE
#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="${DOCKER_ROOT}/shared/backups"
TIMESTAMP="\$(date +%Y-%m-%d_%H-%M-%S)"
HOSTNAME_SHORT="\$(hostname -s)"
ARCHIVE_NAME="\${HOSTNAME_SHORT}_docker_backup_live_\${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="\${BACKUP_ROOT}/\${ARCHIVE_NAME}"
RETAIN_DAYS="${BACKUP_RETAIN_DAYS}"

mkdir -p "\${BACKUP_ROOT}"

echo "[backup-live] Creating archive without stopping containers..."
tar \\
  --exclude="\${BACKUP_ROOT}" \\
  -czf "\${ARCHIVE_PATH}" \\
  -C "\$(dirname "${DOCKER_ROOT}")" "\$(basename "${DOCKER_ROOT}")"

ARCHIVE_SIZE="\$(du -sh "\${ARCHIVE_PATH}" | cut -f1)"
echo "[backup-live] Archive created: \${ARCHIVE_PATH} (\${ARCHIVE_SIZE})"

echo "[backup-live] Generating SHA-256 checksum..."
sha256sum "\${ARCHIVE_PATH}" > "\${ARCHIVE_PATH}.sha256"
echo "[backup-live] Checksum written: \${ARCHIVE_PATH}.sha256"

echo "[backup-live] Pruning archives older than \${RETAIN_DAYS} days..."
find "\${BACKUP_ROOT}" -type f -name "*.tar.gz" -mtime +\${RETAIN_DAYS} -delete
find "\${BACKUP_ROOT}" -type f -name "*.tar.gz.sha256" -mtime +\${RETAIN_DAYS} -delete

echo "[backup-live] Done."
BACKUPLIVE

  chmod +x "${DOCKER_ROOT}/scripts/backup-docker-live.sh"
}

start_stack() {
  log "Starting stack"
  docker compose -f "${DOCKER_ROOT}/compose/core/compose.yaml" up -d
}

print_summary() {
  cat <<SUMMARY

========================================
Config write complete
========================================

Set local DNS or hosts entries:
  ${HOST_IP} ${PORTAINER_DOMAIN} ${HOMEPAGE_DOMAIN}

URLs:
  https://${PORTAINER_DOMAIN}
  https://${HOMEPAGE_DOMAIN}

IMPORTANT: Access Portainer within 5 minutes to create an admin account.
  If the window expires: docker restart portainer

Caddy root CA:
  ${DOCKER_ROOT}/appdata/caddy/data/caddy/pki/authorities/local/root.crt

Suggested cron:
  15 3 * * * ${DOCKER_ROOT}/scripts/backup-docker.sh >> ${DOCKER_ROOT}/shared/backups/backup.log 2>&1

SUMMARY
}

main() {
  require_root
  check_docker
  check_directories
  write_caddyfile
  write_homepage_files
  write_compose_file
  write_backup_scripts
  start_stack
  print_summary
}

main "$@"
