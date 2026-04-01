#!/usr/bin/env bash
# Common functions shared across DockerBox scripts.
# Source this file from any script in the repo root:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

_timestamp() {
	date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
	echo "[$(_timestamp)] [INFO] $*"
}

log_warn() {
	echo "[$(_timestamp)] [WARN] $*" >&2
}

log_error() {
	echo "[$(_timestamp)] [ERROR] $*" >&2
}

# Legacy aliases — prefer log_info / log_warn
log() {
	log_info "$@"
}

warn() {
	log_warn "$@"
}

die() {
	log_error "$*"
	exit 1
}

require_root() {
	if [[ "${EUID}" -ne 0 ]]; then
		die "Please run as root: sudo bash $0"
	fi
}

detect_debian() {
	if [[ ! -f /etc/os-release ]]; then
		die "Cannot detect OS."
	fi

	# shellcheck disable=SC1091
	. /etc/os-release

	if [[ "${ID:-}" != "debian" ]]; then
		die "This script currently supports Debian only."
	fi
}

check_docker() {
	command -v docker >/dev/null 2>&1 || die "Docker is not installed."
	docker version >/dev/null 2>&1 || die "Docker daemon is not available."
}

source_config() {
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
	local config_file="${script_dir}/config.env"
	local config_template="${script_dir}/config.env.example"

	if [[ ! -f "${config_file}" ]]; then
		if [[ -f "${config_template}" ]]; then
			log_error "config.env not found at ${config_file}"
			log_error "Copy config.env.example to config.env and update it for this host."
		else
			log_error "config.env not found at ${config_file}"
		fi
		exit 1
	fi

	# shellcheck disable=SC1090
	source "${config_file}"
}
