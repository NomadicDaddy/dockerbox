# dockerbox

`dockerbox` is a Debian-focused bootstrap repo for bringing up a lightweight Docker host with:

- Docker Engine
- Portainer
- Homepage
- Caddy
- optional Watchtower
- optional Tailscale
- UFW
- backup and restore scripts

The repo is designed to be safe to publish:

- commit `config.env.example`
- keep real `config.env` local and ignored
- generate the runtime stack under `DOCKER_ROOT` (`/opt/docker` by default)

## Fresh machine quick start

On a fresh Debian machine:

```bash
apt update && apt install -y curl
sudo bash <(curl -fsSL https://raw.githubusercontent.com/NomadicDaddy/dockerbox/main/install.sh)
```

Pass `REPO_SLUG=yourname/dockerbox` to override the default repo slug.

## Interactive install

By default, `install.sh` prompts for:

- host IP
- hostname
- primary user
- timezone
- local domains
- Tailscale on/off
- UFW on/off
- unattended upgrades on/off
- SSH hardening on/off
- Watchtower on/off

## Noninteractive install

You can also pass values via environment variables:

```bash
apt update && apt install -y curl
REPO_SLUG="NomadicDaddy/dockerbox" \
NONINTERACTIVE=1 \
HOST_IP="192.168.1.15" \
PRIMARY_USER="youruser" \
PORTAINER_DOMAIN="portainer.home" \
HOMEPAGE_DOMAIN="dash.home" \
INSTALL_TAILSCALE="true" \
ENABLE_WATCHTOWER="true" \
sudo bash <(curl -fsSL https://raw.githubusercontent.com/NomadicDaddy/dockerbox/main/install.sh)
```

## Existing local/manual flow

If you already have the repo locally:

```bash
cp config.env.example config.env
nano config.env
sudo bash bootstrap-host.sh
sudo tailscale up   # if enabled
sudo bash write-configs.sh
```

Or use the convenience wrapper:

```bash
sudo bash init.sh
```

## Files

- `config.env.example` - template config
- `bootstrap-host.sh` - host preparation
- `write-configs.sh` - writes generated configs, compose stack, and backup scripts
- `restore-from-backup.sh` - restores `DOCKER_ROOT` from a backup archive
- `uninstall.sh` - stops stack and removes generated configs (optional: `--remove-docker`, `--remove-data`)
- `init.sh` - local convenience script (copies config, prompts user, runs bootstrap + write-configs)
- `install.sh` - public bootstrap installer
- `lint.sh` - shell script syntax validation (bash -n)
- `lib/common.sh` - shared functions (log_info, log_warn, log_error, die, require_root, detect_debian, check_docker, source_config)
- `scripts/setup-hooks.sh` - installs git pre-commit hook
- `scripts/pre-commit` - pre-commit hook (runs lint + format check)
- `.gitignore` - ignores local config and logs

## Runtime layout

By default the deployed system is written under `/opt/docker`:

- `compose/core/compose.yaml`
- `appdata/portainer`
- `appdata/homepage` (settings.yaml, widgets.yaml, services.yaml, bookmarks.yaml)
- `appdata/caddy` (Caddyfile, data/, config/)
- `scripts/backup-docker.sh`
- `scripts/backup-docker-live.sh`
- `shared/backups`
- `shared/downloads`
- `shared/media`
- `stacks`

## Pre-commit hooks (optional)

To get automatic linting and formatting checks before every commit:

```bash
bash scripts/setup-hooks.sh
```

The hook runs `lint.sh` (shell syntax check) and `bun run format:check` (Prettier) on every `git commit`. To skip it temporarily: `git commit --no-verify`.

## Local DNS / hosts

After install, point these names at your Docker host:

- `portainer.home`
- `dash.home`

Example hosts entry:

```text
192.168.1.15 portainer.home dash.home
```

## Trust Caddy local CA

Import this CA cert on client devices:

```text
/opt/docker/appdata/caddy/data/caddy/pki/authorities/local/root.crt
```

## Post-install

After the stack starts, access Portainer at `https://portainer.home` and create an admin account **within 5 minutes**. If the window expires, restart the container:

```bash
docker restart portainer
```

## Restore

After bootstrapping a fresh Debian host again:

```bash
cp config.env.example config.env
nano config.env
sudo bash restore-from-backup.sh /path/to/backup.tar.gz
```

## Testing strategy

Since DockerBox targets bare-metal Debian hosts, local testing requires a virtual machine.

### Quick VM test (multipass)

Using [Multipass](https://multipass.run/) (cross-platform):

```bash
# Launch a Debian VM
multipass launch --name dockerbox-test --mem 2G --disk 20G debian

# Open a shell in the VM
multipass shell dockerbox-test

# Inside the VM, run the installer
apt update && apt install -y curl
sudo bash <(curl -fsSL https://raw.githubusercontent.com/NomadicDaddy/dockerbox/main/install.sh)
```

### Quick VM test (Vagrant)

```ruby
# Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = 2048
    vb.cpus = 2
  end
  config.vm.provision "shell", inline: "apt update && apt install -y curl"
end
```

```bash
vagrant up
vagrant ssh
sudo bash <(curl -fsSL ...)   # or copy scripts in via synced folder
```

### Quick VM test (Docker — syntax only)

Docker cannot test the full bootstrap (Docker-in-Docker + systemd issues), but it can validate syntax and sourcing:

```bash
docker run --rm -v "$PWD":/dockerbox -w /dockerbox debian:bookworm bash -c '
  bash -n bootstrap-host.sh && echo "bootstrap-host.sh: OK"
  bash -n write-configs.sh && echo "write-configs.sh: OK"
  bash -n restore-from-backup.sh && echo "restore-from-backup.sh: OK"
  bash -n install.sh && echo "install.sh: OK"
  bash -n init.sh && echo "init.sh: OK"
'
```

### What to test end-to-end

On a real or VM Debian host:

1. **Fresh install**: Run `install.sh` (interactive and non-interactive modes)
2. **Stack health**: Verify `docker ps` shows all containers running
3. **Reverse proxy**: `curl -k https://portainer.home` and `curl -k https://dash.home`
4. **Backup + restore**: Run the generated backup script, then `restore-from-backup.sh` on a fresh VM
5. **Uninstall**: Run `uninstall.sh` and verify clean removal

## License

MIT License. See [LICENSE](LICENSE).

## Notes

- Do not put secrets in this repo.
- `config.env` is intentionally gitignored.
- Only Caddy publishes host ports; Portainer and Homepage stay behind the reverse proxy.
- Do not port-forward 80/443 unless you intentionally want public exposure.
- **HARDEN_SSH=true** disables SSH password authentication. Only enable this after confirming SSH key authentication works, otherwise you will be permanently locked out of the machine.

### Watchtower (deprecated)

Watchtower ([containrrr/watchtower](https://github.com/containrrr/watchtower)) was archived on December 17, 2025 and is no longer maintained. It is still available as an optional service in DockerBox but is **disabled by default**.

If you enable Watchtower (`ENABLE_WATCHTOWER=true`):

- The image is pinned to `containrrr/watchtower:1.7.1` (the last release)
- It will never receive security patches or bug fixes
- It has read-write access to the Docker socket
- Consider manual updates instead: `docker compose -f /opt/docker/compose/core/compose.yaml pull && docker compose -f /opt/docker/compose/core/compose.yaml up -d`
