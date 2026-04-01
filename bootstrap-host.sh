#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

# Check for --help before requiring config
for arg in "$@"; do
  case "${arg}" in
    --help)
      cat <<'HELP'
Usage: sudo bash bootstrap-host.sh [OPTIONS]

Host preparation: installs Docker, configures daemon, sets timezone,
creates directory structure under DOCKER_ROOT.

Options:
  --help              Show this help message and exit

Configuration:
  Reads config.env from the script directory. Required variables:
    TZ                  Timezone (e.g., America/Chicago)

  Optional variables:
    HOSTNAME_TO_SET     Set system hostname (blank to skip)
    PRIMARY_USER        User added to docker group
    INSTALL_TAILSCALE   Install Tailscale VPN (true/false)
    ENABLE_UFW          Configure UFW firewall (true/false)
    ENABLE_UNATTENDED_UPGRADES  Enable auto security updates (true/false)
    HARDEN_SSH          Disable SSH password auth (true/false)
    DOCKER_ROOT         Docker data root (default: /opt/docker)

Examples:
  sudo bash bootstrap-host.sh
HELP
      exit 0
      ;;
  esac
done

source_config

# Apply default guards for optional config variables
HOSTNAME_TO_SET="${HOSTNAME_TO_SET:-}"
PRIMARY_USER="${PRIMARY_USER:-}"
TZ="${TZ:-UTC}"
INSTALL_TAILSCALE="${INSTALL_TAILSCALE:-false}"
ENABLE_UFW="${ENABLE_UFW:-false}"
ENABLE_UNATTENDED_UPGRADES="${ENABLE_UNATTENDED_UPGRADES:-false}"
HARDEN_SSH="${HARDEN_SSH:-false}"
DOCKER_ROOT="${DOCKER_ROOT:-/opt/docker}"

if [[ -z "${PRIMARY_USER}" && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  PRIMARY_USER="${SUDO_USER}"
fi

# Validate required config variables
if [[ -z "${TZ}" ]]; then
  die "TZ is required in config.env"
fi

check_primary_user() {
  if [[ -z "${PRIMARY_USER}" ]]; then
    log_warn "PRIMARY_USER is empty. Docker group membership will not be set."
    return
  fi

  if ! id "${PRIMARY_USER}" >/dev/null 2>&1; then
    die "PRIMARY_USER '${PRIMARY_USER}' does not exist."
  fi
}

set_hostname_if_requested() {
  if [[ -n "${HOSTNAME_TO_SET}" ]]; then
    log_info "Setting hostname to ${HOSTNAME_TO_SET}"
    hostnamectl set-hostname "${HOSTNAME_TO_SET}"
  fi
}

install_base_packages() {
  log_info "Installing base packages (skipping already-installed)"
  apt update
  apt upgrade -y

  local packages_to_install=()
  local pkg
  for pkg in ca-certificates curl gnupg lsb-release ufw unattended-upgrades tar nano jq openssh-server; do
    if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
      packages_to_install+=("${pkg}")
    fi
  done

  if [[ ${#packages_to_install[@]} -gt 0 ]]; then
    apt install -y "${packages_to_install[@]}"
  else
    log_info "All base packages already installed"
  fi
}

set_timezone() {
  log_info "Setting timezone to ${TZ}"
  timedatectl set-timezone "${TZ}" || true
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker already installed ($(docker --version 2>/dev/null || echo 'unknown version')), skipping installation"
    return
  fi

  log_info "Installing Docker"
  install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  . /etc/os-release

  cat > /etc/apt/sources.list.d/docker.list <<DOCKERLIST
deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian ${VERSION_CODENAME} stable
DOCKERLIST

  apt update
  apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  systemctl enable --now docker
}

configure_docker_daemon() {
  log_info "Configuring Docker daemon"
  install -m 0755 -d /etc/docker

  cat > /etc/docker/daemon.json <<'DOCKERDAEMON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "userland-proxy": false
}
DOCKERDAEMON

  systemctl restart docker
}

add_user_to_docker_group() {
  if [[ -n "${PRIMARY_USER}" ]]; then
    log_info "Adding ${PRIMARY_USER} to docker group"
    usermod -aG docker "${PRIMARY_USER}"
  fi
}

configure_unattended_upgrades() {
  if [[ "${ENABLE_UNATTENDED_UPGRADES}" != "true" ]]; then
    return
  fi

  log_info "Enabling unattended upgrades"
  dpkg-reconfigure -f noninteractive unattended-upgrades || true
}

install_tailscale() {
  if [[ "${INSTALL_TAILSCALE}" != "true" ]]; then
    return
  fi

  if command -v tailscale >/dev/null 2>&1; then
    log_info "Tailscale already installed ($(tailscale version 2>/dev/null | head -1 || echo 'unknown')), skipping"
    return
  fi

  log_info "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
}

configure_ufw() {
  if [[ "${ENABLE_UFW}" != "true" ]]; then
    return
  fi

  log_info "Configuring UFW"
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow in on tailscale0 || true
  ufw --force enable
  ufw status verbose || true
}

harden_ssh_if_requested() {
  if [[ "${HARDEN_SSH}" != "true" ]]; then
    return
  fi

  log_warn "Only enable HARDEN_SSH if SSH key auth is confirmed working."
  log_info "Hardening SSH"

  local sshd_config="/etc/ssh/sshd_config"
  cp "${sshd_config}" "${sshd_config}.bak.$(date +%Y%m%d%H%M%S)"

  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' \
    "${sshd_config}" || true
  sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' \
    "${sshd_config}" || true
  sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' \
    "${sshd_config}" || true

  grep -q '^PermitRootLogin no' "${sshd_config}" || \
    echo 'PermitRootLogin no' >> "${sshd_config}"
  grep -q '^PasswordAuthentication no' "${sshd_config}" || \
    echo 'PasswordAuthentication no' >> "${sshd_config}"
  grep -q '^PubkeyAuthentication yes' "${sshd_config}" || \
    echo 'PubkeyAuthentication yes' >> "${sshd_config}"

  systemctl restart ssh
}

create_directories() {
  log_info "Creating directory structure"
  mkdir -p "${DOCKER_ROOT}/compose/core"
  mkdir -p "${DOCKER_ROOT}/appdata/portainer"
  mkdir -p "${DOCKER_ROOT}/appdata/homepage"
  mkdir -p "${DOCKER_ROOT}/appdata/caddy/data"
  mkdir -p "${DOCKER_ROOT}/appdata/caddy/config"
  mkdir -p "${DOCKER_ROOT}/shared/backups"
  mkdir -p "${DOCKER_ROOT}/shared/downloads"
  mkdir -p "${DOCKER_ROOT}/shared/media"
  mkdir -p "${DOCKER_ROOT}/scripts"
  mkdir -p "${DOCKER_ROOT}/stacks"

  if [[ -n "${PRIMARY_USER}" ]]; then
    chown -R "${PRIMARY_USER}:${PRIMARY_USER}" "${DOCKER_ROOT}"
  fi
}

print_summary() {
  cat <<SUMMARY

========================================
Host bootstrap complete
========================================

Next:
  1. If Tailscale was installed, run:
     sudo tailscale up

  2. Log out and back in so '${PRIMARY_USER}' gets docker group access.

  3. Run the config script:
     sudo bash ./write-configs.sh

Docker root:
  ${DOCKER_ROOT}

SUMMARY
}

main() {
  require_root
  detect_debian
  check_primary_user
  set_hostname_if_requested
  install_base_packages
  set_timezone
  install_docker
  configure_docker_daemon
  add_user_to_docker_group
  configure_unattended_upgrades
  install_tailscale
  configure_ufw
  harden_ssh_if_requested
  create_directories
  print_summary
}

main "$@"
