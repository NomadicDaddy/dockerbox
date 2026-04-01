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
- `init.sh` - local convenience script (copies config, prompts user, runs bootstrap + write-configs)
- `install.sh` - public bootstrap installer
- `lint.sh` - shell script syntax validation (bash -n)
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
