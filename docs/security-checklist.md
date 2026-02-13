# JBOT — Pre-Launch Security Checklist

## Network & Access Control

- [ ] Traefik `exposedbydefault=false` confirmed in compose command
- [ ] Docker socket proxy (tecnativa) mediates all Docker API access
- [ ] Socket proxy env: only `CONTAINERS=1`, `NETWORKS=1` enabled
- [ ] Internal services bound to entrypoint `:8081` only (not `:80`/`:443`)
- [ ] IP whitelist middleware active for all internal routes
- [ ] Rate limit middleware active on external-facing routes
- [ ] No internal hostnames (`*.internal.local`) resolvable from internet
- [ ] Cloudflare proxied (orange cloud) for any external endpoints

## Authentication & Authorization

- [ ] API key authentication required on all `/v1/*` endpoints
- [ ] API keys stored hashed (bcrypt/argon2) in PostgreSQL — never plaintext
- [ ] `/health` endpoint returns no sensitive data without auth
- [ ] Authentik or Cloudflare Access enforced for external dashboard access
- [ ] Default credentials changed (PostgreSQL, Redis, any admin panels)

## Data Sovereignty & GDPR

- [ ] Zero external API calls for inference (Ollama local only)
- [ ] Qdrant telemetry disabled (`telemetry.enabled: false`)
- [ ] No analytics, tracking, or phone-home in any component
- [ ] Audit log captures: timestamp, user ID, action, model, token count
- [ ] Document upload stores files on local NVMe only (no cloud sync)
- [ ] Data deletion endpoint (`DELETE /v1/documents/{id}`) removes vectors and metadata

## Container Security

- [ ] No container runs as `--privileged`
- [ ] `apparmor: unconfined` only where absolutely required (documented)
- [ ] GPU devices: only `/dev/dri` and `/dev/kfd` passed through
- [ ] Docker daemon `live-restore: true` enabled
- [ ] Log rotation configured (`max-size: 10m`, `max-file: 3`)

## Secrets Management

- [ ] `.env` file has `chmod 600` permissions
- [ ] `.env` is in `.gitignore` — never committed
- [ ] `POSTGRES_PASSWORD` is not the default `changeme_insecure`
- [ ] No hardcoded secrets in compose files or config

## Backup & Recovery

- [ ] Qdrant snapshots scheduled (daily minimum)
- [ ] PostgreSQL `pg_dump` scheduled (daily minimum)
- [ ] Backup restore tested at least once before production
- [ ] ZFS ARC capped to prevent memory pressure on host

## Host Security (Proxmox)

- [ ] SSH hardened (key-only, no root password login)
- [ ] Fail2ban active on Proxmox host
- [ ] Firewall rules restrict LXC egress to required ports only
- [ ] LXC features minimal: `nesting=1,keyctl=1` only
- [ ] Proxmox web UI not exposed to internet
