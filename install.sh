#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-NomadicDaddy/dockerbox}"
BRANCH="${BRANCH:-main}"
DEFAULT_INSTALL_USER="${SUDO_USER:-${USER}}"
DEFAULT_INSTALL_HOME="$(eval echo "~${DEFAULT_INSTALL_USER}")"
INSTALL_DIR="${INSTALL_DIR:-${DEFAULT_INSTALL_HOME}/dockerbox}"
ARCHIVE_URL="https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${BRANCH}"

log() {
  echo
  echo "==> $*"
}

warn() {
  echo
  echo "WARNING: $*" >&2
}

die() {
  echo
  echo "ERROR: $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root. Example: sudo bash install.sh"
  fi
}

detect_debian() {
  if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS."
  fi

  . /etc/os-release

  if [[ "${ID:-}" != "debian" ]]; then
    die "This installer currently supports Debian only."
  fi
}

install_minimum_tools() {
  log "Installing minimum tools"
  apt update
  apt install -y ca-certificates curl tar
}

download_repo() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT

  log "Downloading ${REPO_SLUG}@${BRANCH}"
  curl -fsSL "${ARCHIVE_URL}" -o "${tmp_dir}/repo.tar.gz" || \
    die "Failed to download ${ARCHIVE_URL}. Set REPO_SLUG and BRANCH to published values."

  tar -xzf "${tmp_dir}/repo.tar.gz" -C "${tmp_dir}"

  local extracted_dir
  extracted_dir="${tmp_dir}/$(basename "${REPO_SLUG}")-${BRANCH}"
  [[ -d "${extracted_dir}" ]] || die "Downloaded archive did not unpack as expected."

  mkdir -p "$(dirname "${INSTALL_DIR}")"
  rm -rf "${INSTALL_DIR}"
  mv "${extracted_dir}" "${INSTALL_DIR}"

  rm -rf "${tmp_dir}"
  trap - EXIT
}

ensure_config_file() {
  cd "${INSTALL_DIR}"

  [[ -f config.env.example ]] || die "config.env.example is missing from the repo."

  if [[ ! -f config.env ]]; then
    cp config.env.example config.env
  fi
}

prompt_value() {
  local prompt="$1"
  local default_value="$2"
  local response
  read -r -p "${prompt} [${default_value}]: " response
  if [[ -n "${response}" ]]; then
    printf '%s' "${response}"
  else
    printf '%s' "${default_value}"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default_value="$2"
  local response
  local default_prompt="y/N"

  if [[ "${default_value}" == "true" ]]; then
    default_prompt="Y/n"
  fi

  read -r -p "${prompt} [${default_prompt}]: " response
  response="${response,,}"

  if [[ -z "${response}" ]]; then
    printf '%s' "${default_value}"
    return
  fi

  case "${response}" in
    y|yes|true) printf '%s' "true" ;;
    n|no|false) printf '%s' "false" ;;
    *) printf '%s' "${default_value}" ;;
  esac
}

interactive_config() {
  local host_ip hostname_to_set primary_user tz
  local portainer_domain homepage_domain
  local install_tailscale enable_ufw enable_unattended_upgrades harden_ssh enable_watchtower

  log "Interactive configuration"

  host_ip="$(prompt_value "Host IP" "192.168.1.15")"
  hostname_to_set="$(prompt_value "Hostname to set (blank to skip)" "")"
  primary_user="$(prompt_value "Primary user" "${SUDO_USER:-}")"
  tz="$(prompt_value "Timezone" "America/Chicago")"
  portainer_domain="$(prompt_value "Portainer domain" "portainer.home")"
  homepage_domain="$(prompt_value "Homepage domain" "dash.home")"
  install_tailscale="$(prompt_yes_no "Install Tailscale?" "true")"
  enable_ufw="$(prompt_yes_no "Enable UFW?" "true")"
  enable_unattended_upgrades="$(prompt_yes_no "Enable unattended upgrades?" "true")"
  harden_ssh="$(prompt_yes_no "Disable SSH password auth now?" "false")"
  enable_watchtower="$(prompt_yes_no "Enable Watchtower (archived, unmaintained)?" "false")"

  cat > "${INSTALL_DIR}/config.env" <<EOF
HOST_IP="${host_ip}"
HOSTNAME_TO_SET="${hostname_to_set}"
PRIMARY_USER="${primary_user}"

TZ="${tz}"

PORTAINER_DOMAIN="${portainer_domain}"
HOMEPAGE_DOMAIN="${homepage_domain}"

INSTALL_TAILSCALE="${install_tailscale}"
ENABLE_UFW="${enable_ufw}"
ENABLE_UNATTENDED_UPGRADES="${enable_unattended_upgrades}"
HARDEN_SSH="${harden_ssh}"
ENABLE_WATCHTOWER="${enable_watchtower}"

DOCKER_ROOT="/opt/docker"
BACKUP_RETAIN_DAYS="14"

PORTAINER_IMAGE="portainer/portainer-ce:2"
HOMEPAGE_IMAGE="ghcr.io/gethomepage/homepage:latest"
WATCHTOWER_IMAGE="containrrr/watchtower:1.7.1"
CADDY_IMAGE="caddy:2"
EOF
}

apply_env_overrides() {
  cd "${INSTALL_DIR}"

  local keys=(
    HOST_IP
    HOSTNAME_TO_SET
    PRIMARY_USER
    TZ
    PORTAINER_DOMAIN
    HOMEPAGE_DOMAIN
    INSTALL_TAILSCALE
    ENABLE_UFW
    ENABLE_UNATTENDED_UPGRADES
    HARDEN_SSH
    ENABLE_WATCHTOWER
    DOCKER_ROOT
    BACKUP_RETAIN_DAYS
    PORTAINER_IMAGE
    HOMEPAGE_IMAGE
    WATCHTOWER_IMAGE
    CADDY_IMAGE
  )

  local key value escaped_value
  for key in "${keys[@]}"; do
    value="${!key:-}"
    if [[ -n "${value}" ]]; then
      escaped_value="${value//\\/\\\\}"
      escaped_value="${escaped_value//&/\\&}"
      sed -i "s|^${key}=.*|${key}=\"${escaped_value}\"|" config.env
    fi
  done
}

run_setup() {
  cd "${INSTALL_DIR}"

  log "Running bootstrap-host.sh"
  bash ./bootstrap-host.sh

  if grep -q '^INSTALL_TAILSCALE="true"$' config.env; then
    warn "If desired, run 'sudo tailscale up' after install."
  fi

  log "Running write-configs.sh"
  bash ./write-configs.sh
}

print_done() {
  cat <<EOF

========================================
Install complete
========================================

Working directory:
  ${INSTALL_DIR}

You may want to:
  1. Access Portainer within 5 minutes to create an admin account
     (if expired: docker restart portainer)
  2. Run: sudo tailscale up
  3. Add local DNS or hosts entries
  4. Trust Caddy's local CA:
     /opt/docker/appdata/caddy/data/caddy/pki/authorities/local/root.crt

EOF
}

main() {
  require_root
  detect_debian
  install_minimum_tools
  download_repo
  ensure_config_file

  if [[ -n "${NONINTERACTIVE:-}" ]]; then
    log "Using noninteractive mode with environment overrides"
  else
    interactive_config
  fi

  apply_env_overrides
  run_setup
  print_done
}

main "$@"
