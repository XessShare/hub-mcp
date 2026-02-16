# 90-Day Tactical Plan & Roadmap

> Prioritized, actionable implementation plan for stabilizing the FitnaAI
> platform and achieving pilot-customer readiness within 90 days.

---

## Critical Path

```
Week 1-4: Stability + Security
Week 5-8: Compliance + Documentation
Week 9-12: AI Enablement + Pilot Readiness
```

Everything else (second node, ZFS, CI/CD, hybrid cloud) comes after and gets
prioritized by revenue and customer feedback.

---

## Week 1-2: Foundation Hardening

| # | Action | Owner | Effort | Risk Mitigated |
|---|--------|-------|--------|----------------|
| 1 | **Restore test:** Restore vzdump backup of a VM to different storage, validate function | Jonas | 3-4h | "Backup not restorable" (CRITICAL) |
| 2 | **auditd on host:** Install + configure syscall logging for root actions | Jonas | 1-2h | Missing audit trail (MEDIUM) |
| 3 | **SSH hardening validation:** Check sshd_config against target state, create key inventory | Jonas | 1h | SSH brute-force risk (MEDIUM) |
| 4 | **Proxmox MFA:** Activate TOTP for Web-UI login | Jonas | 30 min | Proxmox UI compromise (CRITICAL) |
| 5 | **Samba hardening:** SMBv3-only, signing, restrict to management IP, audit logging | Jonas | 2h | Samba compromise (HIGH) |
| 6 | **Backup encryption:** Configure vzdump with AES-256 | Jonas | 1h | Backup data theft (HIGH) |

**Total estimated effort: ~9-11h**

---

## Week 3-4: Observability Bootstrap

| # | Action | Owner | Effort | Risk Mitigated |
|---|--------|-------|--------|----------------|
| 7 | **node_exporter:** Install on host + AI-VM | Jonas | 1h | Basis for host monitoring |
| 8 | **Prometheus targets:** Configure node_exporter, cadvisor, Traefik metrics | Jonas | 2h | Basis for all metrics |
| 9 | **3 Grafana dashboards:** Host health, Docker stack, GPU (via rocm-smi exporter or custom) | Jonas | 4h | Full stack visibility |
| 10 | **Alerting:** Disk > 90%, container crash loop, backup failure -> notification (email or Telegram) | Jonas | 2h | "Silent failures" risk |
| 11 | **Log retention policy:** Define Traefik 30d, Security 90d, Audit 365d | Jonas | 1h | DSGVO compliance |

**Total estimated effort: ~10h**

---

## Week 5-8: Compliance & Documentation

| # | Action | Owner | Effort | Risk Mitigated |
|---|--------|-------|--------|----------------|
| 12 | **VVT (Verzeichnis der Verarbeitungstaetigkeiten):** Create processing activities register | Jonas | 4h | DSGVO obligation (CRITICAL) |
| 13 | **TOM document:** Document technical + organizational measures | Jonas | 3h | DSGVO obligation |
| 14 | **AV contract template:** Create based on Bitkom/industry templates | Jonas | 3h + lawyer | DSGVO obligation before customer ops |
| 15 | **AI Act risk classification:** Classify per use case (see security-compliance.md) | Jonas | 3h | AI Act compliance |
| 16 | **Runbooks:** Host restart, VM recovery, Docker stack restart, backup restore, GPU passthrough recovery | Jonas | 6h | Single-operator risk |
| 17 | **Architecture diagram:** Current state, one page | Jonas | 2h | Documentation, onboarding |
| 18 | **Password safe:** Set up Bitwarden/KeePass, populate with all credentials | Jonas | 2h | Bus-factor risk |

**Total estimated effort: ~23h + optional lawyer consultation**

---

## Week 9-12: AI Enablement & Pilot Readiness

| # | Action | Owner | Effort | Risk Mitigated |
|---|--------|-------|--------|----------------|
| 19 | **jbot-api: API key auth** | Jonas | 4-6h | Open API risk (CRITICAL for customer ops) |
| 20 | **Qdrant: API key + backup script** | Jonas | 2h | Data security |
| 21 | **Redis: AUTH password** | Jonas | 30 min | Container security |
| 22 | **Offsite backup:** External HDD, weekly, encrypted | Jonas | 2h + hardware | Data loss on hardware failure (CRITICAL) |
| 23 | **Identify + approach pilot customers** | Jonas | Ongoing | Product-market-fit validation |
| 24 | **Define pilot onboarding process:** What does customer need? What does FitnaAI deliver? Billing? | Jonas | 4h | Business readiness |
| 25 | **Quarterly restore drill** | Jonas | 3h | Backup validation |

**Total estimated effort: ~16-18h + ongoing customer outreach**

---

## 90-Day Success Criteria

| Criterion | Measurable Target |
|-----------|------------------|
| Restore capability | At least 1 successful restore test documented |
| Monitoring | 3 active Grafana dashboards, alerting for critical events |
| Security | MFA on Proxmox, auditd active, Samba hardened, backup encrypted |
| Compliance | VVT, TOM document, and AV contract template exist |
| AI readiness | jbot-api has authentication, Qdrant/Redis secured |
| Business | At least 1 pilot customer identified or onboarded |
| Documentation | Runbooks for 5 critical scenarios, architecture diagram current |
| Knowledge resilience | Password safe populated, emergency procedures documented |

---

## 3-12 Month Expansion Plan

### AI Cluster Scaling

| Timeframe | Action | Prerequisite |
|-----------|--------|-------------|
| Month 4-6 | Evaluate second node: budget, hardware specs, Proxmox cluster setup | At least 1 paying pilot |
| Month 6-8 | Set up second node: ZFS-on-Root, Proxmox cluster join, Corosync HA | Budget + hardware available |
| Month 8-10 | Storage replication: ZFS send/receive between nodes (or Ceph at 3+ nodes) | Second node operational |
| Month 10-12 | Optional third node or dedicated GPU node (possibly NVIDIA for broader model compatibility) | Revenue justifies investment |

### Storage Redundancy

- **Short-term:** External HDD for offsite backup
- **Medium-term:** NAS (e.g., Synology, TrueNAS) for automated backups + NFS storage
- **Long-term:** ZFS mirror on second node or Proxmox-native Ceph (at 3+ nodes)

### CI/CD Pipeline

**Phase 1 (Month 3-4): Git-based deployment**
- All scripts + compose files in Git
- Manual pull + deploy on VM
- Changelog in Git

**Phase 2 (Month 6-8): Automated deployment**
- Gitea (self-hosted) or GitHub Actions
- Trigger: push to main -> build -> test -> deploy to staging VM -> health check
- Staging VM: clone of AI-VM for pre-deployment tests

**Phase 3 (Month 9-12): Full CI/CD**
- Infrastructure-as-Code: Proxmox API-based VM provisioning
- Automated security scanning: Trivy (containers), OWASP ZAP (API)
- Policy-as-Code: automated compliance checks

### EU Cloud Bridge (Optional)

Only if clear customer demand exists:
- Hetzner Cloud (German, DSGVO-compliant, good price-performance)
- IONOS / OVH as alternatives
- Hybrid model: inference on-prem, frontend/API in EU cloud
- **Do not pre-build without customer demand.**

---

## Risk-Impact Mapping

Each 90-day action mapped to the risks it mitigates:

```
R01 (SSD failure -> data loss)
  <- #22 Offsite backup

R02 (ROCm update breaks GPU)
  <- Snapshot strategy (existing), #16 Runbooks (GPU recovery)

R03 (Proxmox UI without MFA)
  <- #4 Proxmox MFA

R04 (Samba compromise)
  <- #5 Samba hardening

R05 (Open API)
  <- #19 API key auth

R06 (No audit trail)
  <- #2 auditd

R07 (No VVT)
  <- #12 VVT creation

R08 (No AV contracts)
  <- #14 AV contract template

R10 (Bus factor = 1)
  <- #16 Runbooks, #17 Architecture diagram, #18 Password safe

R11 (Backup untested)
  <- #1 Restore test, #25 Quarterly drill

R12 (No PMF validated)
  <- #23 Pilot customer outreach, #24 Onboarding process

R15 (Unencrypted backups)
  <- #6 Backup encryption
```
