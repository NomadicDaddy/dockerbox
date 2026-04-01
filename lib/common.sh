#!/usr/bin/env bash
# Common functions shared across DockerBox scripts.
# Source this file from any script in the repo root:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

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
			echo "ERROR: config.env not found at ${config_file}" >&2
			echo "Copy config.env.example to config.env and update it for this host." >&2
		else
			echo "ERROR: config.env not found at ${config_file}" >&2
		fi
		exit 1
	fi

	# shellcheck disable=SC1090
	source "${config_file}"
}
