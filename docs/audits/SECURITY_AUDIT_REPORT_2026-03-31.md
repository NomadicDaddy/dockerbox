# Security Audit Report — 2026-03-31

## Executive Summary

**Application**: dockerbox
**Overall Score**: 88/100
**Risk Level**: LOW
**Critical Issues Found**: 0
**High Priority Issues Found**: 0
**Medium Priority Issues Found**: 2
**Low Priority Issues Found**: 5

Dockerbox is a pure shell script infrastructure project with no web application attack surface. The security posture is strong for its category: secrets are properly excluded from version control, scripts use strict mode, inputs are escaped, and HTTPS is used for all external downloads. No critical or high severity issues were found.

## Security Architecture Assessment

- **Authentication model**: N/A (infrastructure bootstrap, not a web app)
- **Secret management**: config.env gitignored, config.env.example committed with safe defaults
- **Network security**: UFW firewall, Caddy reverse proxy with security headers, optional SSH hardening
- **Container security**: Docker socket access scoped per container (RO for Homepage, RW for Portainer)
- **TLS**: Caddy local CA with auto-generated certificates

## Key Metrics

| Metric                   | Value                                                            |
| ------------------------ | ---------------------------------------------------------------- |
| Files audited            | 10 (6 shell scripts, 1 CI workflow, 2 config files, 1 gitignore) |
| Lines reviewed           | ~1,320                                                           |
| Hardcoded secrets found  | 0                                                                |
| .env files found         | 0                                                                |
| Unescaped variable usage | 0                                                                |

## Detailed Findings

### Medium Priority

#### M1: Curl-pipe-bash pattern for Tailscale installation

- **Severity**: Medium
- **Location**: `bootstrap-host.sh:172`
- **Evidence**: `curl -fsSL https://tailscale.com/install.sh | sh`
- **Impact**: If the HTTPS connection is intercepted or Tailscale's CDN is compromised, arbitrary code executes as root. The `-f` flag causes curl to fail on HTTP errors but does not prevent content tampering at the source.
- **Mitigating factors**: HTTPS is used, Tailscale is a reputable vendor, this is their official install method, and the script only runs during initial bootstrap (not recurring).
- **Recommendation**: Accept as standard practice. Optionally document the risk in README for security-conscious users, or provide an alternative manual install path.
- **Effort**: Informational — no code change required

#### M2: Docker socket full read-write access to Portainer

- **Severity**: Medium
- **Location**: `write-configs.sh:202`
- **Evidence**: `- /var/run/docker.sock:/var/run/docker.sock` (no `:ro` flag)
- **Impact**: If Portainer is compromised, an attacker gains full Docker daemon control — equivalent to root access on the host. This is a known trade-off inherent to Docker management UIs.
- **Mitigating factors**: Portainer is behind Caddy reverse proxy (not directly exposed on host ports), Caddy enforces HTTPS with security headers, UFW restricts network access.
- **Recommendation**: Accept as inherent to Portainer's function. Ensure Portainer admin credentials are set during first access. Consider documenting the risk.
- **Effort**: Informational — no code change required

### Low Priority

#### L1: No integrity verification on downloaded archives

- **Severity**: Low
- **Location**: `bootstrap-host.sh:108` (Docker GPG key), `install.sh:57` (repo archive)
- **Evidence**: Downloads via `curl -fsSL` over HTTPS but no checksum or signature verification beyond TLS.
- **Impact**: Standard for infrastructure bootstrap scripts. TLS provides transport security; GPG key is used for Docker package verification downstream.
- **Recommendation**: Accept as standard practice.
- **Effort**: N/A

#### L2: Backup archive restored without integrity check

- **Severity**: Low
- **Location**: `restore-from-backup.sh:62`
- **Evidence**: `tar -xzf "${BACKUP_ARCHIVE}" -C "$(dirname "${DOCKER_ROOT}")"` — no checksum or signature verification before extraction.
- **Impact**: If an attacker substitutes a malicious backup archive, it would be extracted as-is. However, restore requires root access and a local file path, limiting the attack surface to users who already have root.
- **Recommendation**: Optionally add SHA-256 checksum verification. Low priority since the threat model assumes trusted local access.
- **Effort**: 1 hour

#### L3: GitHub Actions checkout not pinned to commit SHA

- **Severity**: Low
- **Location**: `.github/workflows/validate.yml:12`
- **Evidence**: `uses: actions/checkout@v4` — pinned to major version tag, not a specific commit SHA.
- **Impact**: A supply chain attack on the `actions/checkout` repository could inject malicious code. However, this is an official GitHub-maintained action with strong security controls.
- **Recommendation**: Optionally pin to a specific SHA for maximum supply chain security: `uses: actions/checkout@<sha>`. Low priority given the action's provenance.
- **Effort**: 5 minutes

#### L4: HOMEPAGE_ALLOWED_HOSTS wildcard

- **Severity**: Low
- **Location**: `write-configs.sh:222`
- **Evidence**: `HOMEPAGE_ALLOWED_HOSTS: "*"`
- **Impact**: Allows Homepage to respond to any Host header. In isolation this could enable host header injection, but Homepage is behind Caddy reverse proxy which controls routing, so direct access is not possible from the network.
- **Recommendation**: Accept — the reverse proxy architecture mitigates this. Optionally restrict to the configured `HOMEPAGE_DOMAIN` value for defense in depth.
- **Effort**: 5 minutes

#### L5: Caddy TLS skip verify for Portainer

- **Severity**: Low
- **Location**: `write-configs.sh:78`
- **Evidence**: `tls_insecure_skip_verify` in Caddy reverse proxy config for Portainer
- **Impact**: Caddy does not verify Portainer's self-signed certificate when proxying. Since both run in the same Docker compose network, the risk of MITM between containers is negligible.
- **Recommendation**: Accept — this is standard for reverse-proxying to self-signed internal services.
- **Effort**: N/A

## Compliance Assessment

### Adapted OWASP Top 10 (Infrastructure Context)

| OWASP Category                | Status | Notes                                                                      |
| ----------------------------- | ------ | -------------------------------------------------------------------------- |
| A01 Broken Access Control     | Pass   | Scripts require root, UFW restricts network, services behind reverse proxy |
| A02 Cryptographic Failures    | Pass   | Caddy auto-TLS, no secrets in repo, bcrypt not applicable (no user auth)   |
| A03 Injection                 | Pass   | All variables properly quoted, sed inputs escaped (install.sh:190-192)     |
| A04 Insecure Design           | Pass   | Defense in depth: UFW + Caddy + Docker network isolation                   |
| A05 Security Misconfiguration | Pass   | No .env files, config.env gitignored, strict mode on all scripts           |
| A06 Vulnerable Components     | Pass   | Uses official Docker/vendor images, Watchtower for updates                 |
| A07 Authentication Failures   | N/A    | No application-level authentication (Portainer handles its own)            |
| A08 Software/Data Integrity   | Pass   | HTTPS for all downloads, `set -euo pipefail` prevents silent failures      |
| A09 Logging Failures          | Pass   | Docker daemon configured with log rotation (10MB, 3 files)                 |
| A10 SSRF                      | N/A    | No server-side request handling                                            |

## Best Practices Assessment

### Followed

- [x] Strict bash mode (`set -euo pipefail`) on all scripts
- [x] All variables properly quoted (`"${VAR}"` syntax throughout)
- [x] Sed input escaping for backslashes and ampersands (`install.sh:190-191`)
- [x] Config secrets excluded from version control (`.gitignore` includes `config.env`)
- [x] No hardcoded credentials, passwords, or API keys
- [x] HTTPS used for all external downloads
- [x] UFW firewall with explicit allow rules (deny incoming by default)
- [x] SSH hardening available (disabled by default for safety)
- [x] Docker daemon logging configured with rotation limits
- [x] Caddy security headers (X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy)
- [x] Server header removed by Caddy (`-Server`)
- [x] Homepage gets read-only Docker socket access (`:ro`)
- [x] Backup scripts exclude their own output directory (prevents recursive backup)
- [x] SSH config backed up before modification (`bootstrap-host.sh:200`)

### Missing (informational)

- [ ] No checksum verification on downloaded archives (standard for infra scripts)
- [ ] No shellcheck in CI (only `bash -n` syntax checking)
- [ ] No backup archive integrity verification

## Action Plan

### Immediate (0-1 week)

No critical or high priority items. Codebase is release-ready from a security perspective.

### Short-term (1-4 weeks)

1. Consider documenting the Docker socket risk and Portainer admin setup in README
2. Optionally pin GitHub Actions to commit SHAs

### Long-term (1-3 months)

1. Add shellcheck to CI for deeper static analysis of shell scripts
2. Consider backup integrity verification (SHA-256 sidecar files)
3. Monitor for CVEs in container images (Portainer, Homepage, Caddy, Watchtower)
