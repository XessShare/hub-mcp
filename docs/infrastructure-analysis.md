# FitnaAI Infrastructure & Platform Strategy Analysis

> Full infrastructure, security, and platform analysis for the FitnaAI
> Proxmox-based hybrid virtualization environment. Analyzed from three roles:
> Project Manager, Project Leadership, and IT Security & Compliance.

---

## Executive Summary

| Dimension | Score | Assessment |
|-----------|-------|------------|
| Infrastructure Maturity | **2.5 / 5** | Functional, script-based, not redundant, not fully observable |
| Security Posture | **2 / 5** | Basic hardening present, no Zero Trust, no IDS, no encryption at rest |
| AI-Readiness (Technical) | **6 / 10** | ROCm stack works, Ollama + Qdrant + FastAPI pipeline operational |
| AI-Readiness (Commercial) | **2 / 10** | No pilot customers, no SLAs, no compliance docs, no pricing |
| Scalability | **Limited** | Single-Node, Single-GPU, Single-Operator SPOFs |

### Top 5 Management Decisions

| # | Decision | Urgency |
|---|----------|---------|
| 1 | **Restore-Test** — Without validated restore, backup concept is hypothesis | IMMEDIATE |
| 2 | **DSGVO base documentation** — VVT, TOM document, AV contract templates. No EU customer ops without these | Within 30 days |
| 3 | **Activate monitoring** — Prometheus + Grafana are defined in stack but without dashboards/alerting, observability is lip service | Within 30 days |
| 4 | **ZFS vs. LVM storage strategy decision** — Fundamentally impacts backup, snapshots, replication, scaling path | Within 60 days |
| 5 | **Onboard first pilot customer** with bounded scope — Without real customer contact, platform remains a tech project | Within 90 days |

---

## 1. Current State Assessment

### 1.1 Technical Infrastructure

**Proxmox Host Configuration & Root Policy**

Root-Execution-Policy is clearly defined: all host scripts run as root, no sudo. This eliminates sudo-timeout errors, PATH inconsistencies, and privilege escalation issues. However, there's no command-level audit trail — when root works directly, there's no `sudo`-log attributing actions.

Required mitigations:
- `auditd` on host (syscall-level logging)
- `.bash_history` with timestamps (`HISTTIMEFORMAT`) and append-only (`chattr +a`)
- Long-term: bastion host concept or session recording for all root sessions

**Network Segmentation**

| Layer | Status | Assessment |
|-------|--------|------------|
| Host <-> VMs | vmbr0-based, flat /16 | Functional but NAT is not a security feature. No explicit microsegmentation |
| Docker Networks | `jbot-internal` (internal: true), `jbot-proxy` (external via Traefik) | **Good.** Internal/proxy separation is solid |
| VM <-> VM | Implicit via Proxmox bridges | No explicit firewall rules between VMs documented |
| Client <-> Host | SSH + Web-UI + RDP/SPICE | Too many attack surfaces without clear segmentation |

**GPU Passthrough Status**

- AMD RX 6800 XT via IOMMU/VFIO -> Linux GPU-VM
- ROCm 6.x with `HSA_OVERRIDE_GFX_VERSION=10.3.0` for Navi 21
- compose.override.yaml maps `/dev/kfd` + `/dev/dri` into Ollama container
- Groups: video + render

Stability risks:
- No GPU health monitoring (temperature, VRAM usage, error rates)
- No automatic detection of GPU passthrough failures after host reboot
- No documented recovery procedure for GPU passthrough failure
- ROCm updates can break the stack — snapshot `rocm-working` is critical golden state

**Backup Strategy**

- vzdump + cron-based
- Snapshot strategy: `pre-<change>`, `rocm-working`, `full-stack`
- Long-term backups via vzdump snapshots

**CRITICAL:** No documented restore test exists. Backups likely reside on same physical machine — hardware failure means primary data AND backups lost simultaneously.

**Monitoring**

Prometheus + Grafana defined in docker-compose (profile "monitoring"), Traefik access logs configured. But "defined" != "actively used". Open questions:
- Which metrics are actually scraped?
- Are there dashboards?
- Is alerting configured (AlertManager, Grafana Alerts)?
- Are host metrics (node_exporter) captured?
- Are GPU metrics captured?

**Monitoring maturity: 1/5**

**Attack Surface**

| Service | Exposure | Risk |
|---------|----------|------|
| SSH (Host) | Network | Hardened (assumed: key-only, Fail2Ban) — **Medium** |
| Proxmox Web-UI (8006) | Network | Self-signed TLS, admin access — **High** |
| Traefik (80/443) | Network (potentially external) | Reverse proxy, TLS — **Medium** |
| Samba (445) | LAN | SMBv1 disabled? Guest access? — **Medium to High** |
| RDP/SPICE | Network | Windows VM reachable? — **Medium** |
| Ollama API | Docker internal via jbot-internal | **Low** (good isolation) |
| Qdrant API | Docker internal | **Low** |

**Infrastructure Maturity Breakdown**

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Provisioning | 3/5 | Cloud-Init templates, script-based |
| Backup | 2/5 | Present but untested, no offsite |
| Monitoring | 1.5/5 | Defined, not operational |
| Network | 2.5/5 | Docker isolation good, host/VM layer weak |
| Documentation | 2/5 | Phase-4 validation exists, no complete runbook set |
| Automation | 3/5 | Scripts present, deterministic deployments |

---

### 1.2 Strategic Positioning

**FitnaAI as On-Prem/SME AI Agent Platform in the EU**

- **Data sovereignty** is increasingly sellable in the EU, especially post-AI Act
- **On-prem inference** with local LLMs eliminates dependency on cloud API providers
- **AMD/ROCm** vs NVIDIA/CUDA is a differentiator (cost structure, independence) but also a technical risk (less mature ecosystem)

**AI Workload Readiness**

| Component | Status | Gap |
|-----------|--------|-----|
| LLM Inference (Ollama) | Functional | Single-GPU, no multi-model scheduling |
| Vector DB (Qdrant) | Functional | No backup strategy for collections, no access control |
| API Layer (jbot-api/FastAPI) | Functional | No AuthN/AuthZ, no app-level rate limiting |
| Orchestration | docker compose | No Kubernetes, no auto-scaling, no health-check restart |
| Monitoring | Partial | No AI-specific monitoring (inference latency, tokens/s) |

**Scaling Limits**

- **GPU:** Single RX 6800 XT, 16 GB VRAM. Handles 7B-13B models, not 70B
- **Storage:** Single SSD. No RAID, no ZFS mirror. Hardware failure = data loss
- **Single-Node:** No failover. Proxmox host failure = total outage

**Homelab -> Production Platform Gap**

| Criterion | Homelab Status | Production Requirement | Gap |
|-----------|---------------|----------------------|-----|
| Redundancy | None | N+1 for critical components | Large |
| SLAs | None | 99.5%+ availability | Large |
| Access Control | root-based | RBAC, audit trail, MFA | Medium |
| Monitoring & Alerting | Partially defined | 24/7 alerting, dashboards, runbooks | Medium |
| Compliance | Not addressed | DSGVO, AI Act | Large |
| Backup/Restore | Present/untested | Tested, offsite, encrypted | Large |

---

### 1.3 Resources & Feasibility

**Single Operator Reality**

Jonas is single operator. Every hour of infrastructure work is one less hour of product development. There is no four-eyes principle for changes.

**Recommendation:** Strict time budgeting. Max 30% of available time for infrastructure, 70% for product and customer acquisition. Automation is the lever.

**Automation Degree**

| Area | Level | Rating |
|------|-------|--------|
| VM Provisioning | High (Cloud-Init templates) | Good |
| Host Configuration | Medium (scripts, validate-phase4.sh) | Good |
| Docker Stack Deployment | High (docker compose) | Good |
| Backup | Medium (vzdump + cron) | No automated restore test |
| Monitoring Setup | Low (defined, not operational) | Needs work |
| Security Hardening | Low (manual, not as code) | Needs work |
| Compliance Documentation | None | Critical gap |

**Single Points of Failure**

| SPOF | Type | Impact on Failure |
|------|------|------------------|
| Jonas | Person | Total operations outage |
| Proxmox Host (hardware) | Hardware | Total service outage |
| Omarchy M2 SSD | Hardware | Data loss (if no offsite backup) |
| AMD RX 6800 XT | Hardware | No GPU inference |
| Internet connection | Network | No remote access, no updates |

---

### 1.4 Risk Register

#### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| SSD hardware failure -> data loss | Medium | **Critical** | Offsite backup, evaluate ZFS mirror |
| ROCm update breaks GPU stack | High | High | Snapshot `rocm-working` as golden state, pin ROCm version |
| Docker image supply chain attack | Low | High | Pin images (SHA256), scan regularly (Trivy) |
| Proxmox host kernel panic | Low | Critical | UPS, hardware monitoring, second node long-term |
| Network misconfiguration after change | Medium | Medium | Extend validate-phase4.sh, snapshot before every network change |

#### Security Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Samba share compromise (LAN attack) | Medium | High | SMB hardening, restrict to specific IPs, SMBv3-only, audit logging |
| Proxmox Web-UI without MFA | Medium | Critical | Activate MFA (TOTP), restrict to management VLAN |
| Container isolation failure (Docker breakout) | Low | Critical | AppArmor/Seccomp profiles, no `--privileged` containers |
| SSH brute-force despite Fail2Ban | Low | Medium | Validate key-only auth, review Fail2Ban config |
| No audit trail for root actions | High | Medium | Implement auditd, set HISTTIMEFORMAT |

#### Compliance Risks (DSGVO / AI Act)

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Customer data on Samba without encryption at rest | High | High | LUKS or ZFS encryption, access ACLs |
| No AV contracts with customers | High (at customer ops) | Critical | Create AV contract template before first customer |
| No Verzeichnis der Verarbeitungstaetigkeiten (VVT) | High | High | Create VVT (DSGVO Art. 30) |
| AI Act: missing risk classification of agents | Medium | High | Perform use-case-based classification |
| PII in Traefik/jbot logs without legal basis | Medium | Medium | Define log retention periods, PII minimization |

#### Operational Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Jonas unavailable (illness, vacation) | Medium | Critical | Create runbooks, document emergency access |
| Uncontrolled changes (no change control) | High | Medium | Change log (Git-based minimum), snapshot before every change |
| Backup present but not restorable | Medium | Critical | Quarterly restore drill |

#### Strategic Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| AMD/ROCm ecosystem stagnates | Medium | High | Evaluate NVIDIA compatibility path |
| No product-market fit | Medium | Critical | Onboard pilot customers quickly, build feedback loop |
| Over-engineering infrastructure before customer demand | High | Medium | "Good enough for pilot" as target |

---

## 2. Strategic & Tactical Planning

### 2.1 Architecture Roadmap (12 Months)

**Phase 1: Stabilization (Months 1-2)**
- Restore test + documentation
- Offsite backup (minimum USB HDD, better NAS or remote)
- Monitoring activation: node_exporter, Prometheus targets, 3 Grafana dashboards
- Alerting: disk space, CPU load, container restarts, backup failure
- DSGVO base documentation (VVT, TOM document)
- Samba hardening
- auditd on host

**Phase 2: Observability (Months 2-4)**
- Log centralization (Loki + Grafana recommended)
- AI-specific metrics: inference latency, tokens/s, model load times, VRAM usage
- Dashboard set: operator (daily), management (weekly)
- Alerting tuning: false-positive reduction, severity levels

**Phase 3: AI Enablement (Months 3-6)**
- jbot-api AuthN/AuthZ (API keys, then JWT/OAuth2)
- Qdrant access control + backup strategy for collections
- Multi-model management: Ollama model registry, auto load/unload
- Agent templates: reproducible agent configs as code
- AI Act documentation per use case

**Phase 4: Resilience & Redundancy (Months 6-9)**
- Second node evaluation and procurement (Proxmox cluster with 2 nodes)
- Storage redundancy: ZFS mirror or Ceph
- Network redundancy: second switch, LACP/bonding
- Automated failover for critical VMs (Proxmox HA with Corosync)

**Phase 5: Automation & Policy-as-Code (Months 9-12)**
- All host scripts in Git with versioning
- CI/CD pipeline for infrastructure changes
- Policy-as-Code: OPA/Gatekeeper or shell-based policy checks
- Automated compliance checks
- Infrastructure tests: InSpec or Serverspec

### 2.2 Infrastructure Optimization

**Monitoring Implementation Plan**

```
Scrape Targets:
  node_exporter (Host)        -> CPU, RAM, Disk, Network
  node_exporter (AI-VM)       -> VM resources
  cadvisor                    -> Docker container metrics
  traefik /metrics            -> Request rate, latency, errors
  ollama /api/health + custom -> Inference metrics
  qdrant /metrics             -> Collection size, query latency
  redis /metrics              -> Cache hit rate, memory

Dashboards:
  Operator Dashboard   -> Host health, container status, GPU temp/VRAM
  AI Dashboard         -> Inference latency, tokens/s, model status
  Security Dashboard   -> Fail2Ban events, Traefik 403/401, SSH logins

Alerting:
  CRITICAL -> Disk > 90%, container crash loop, backup failure
  WARNING  -> CPU > 80% sustained, RAM > 85%, GPU temp > 85C
  INFO     -> SSH login, model change, config change
```

**Log Centralization (Grafana Loki recommended)**

```
Log Sources:
  Traefik access logs  -> JSON format, to Loki via Promtail
  jbot-api logs        -> stdout -> Docker log driver -> Promtail
  System logs (Host)   -> journald -> Promtail
  Samba audit logs     -> Promtail
  auditd logs          -> Promtail
  Ollama logs          -> stdout -> Docker log driver -> Promtail

Retention:
  Operational logs     -> 30 days
  Security logs        -> 90 days
  Audit logs           -> 365 days (DSGVO-relevant)
  AI decision logs     -> min 6 months (AI Act requirement)
```

**ZFS vs. LVM Decision**

| Criterion | LVM | ZFS |
|-----------|-----|-----|
| Complexity | Low | Medium to High |
| Snapshots | Basic | Excellent (CoW, incremental) |
| Data Integrity | No checksums | End-to-end checksums |
| Compression | None (native) | Inline (LZ4, ZSTD) |
| Replication | Not native | zfs send/receive (incremental, remote) |
| Proxmox Integration | Native | Excellent (ZFS-on-Root standard option) |

**Recommendation:** ZFS when second node arrives. For current single-SSD config, limited benefit (no mirror possible). ZFS-on-Root for second node from the start.

**Recommended Network Schema**

```
Host Management:      10.0.0.0/24
  Proxmox Host:       10.0.0.1
  ThinkPad:           10.0.0.10

VM Network:           10.0.1.0/24
  Windows VM:         10.0.1.10
  Linux AI VM:        10.0.1.20

Docker (internal):    172.18.0.0/16 (docker compose default)
  jbot-internal:      172.18.1.0/24
  jbot-proxy:         172.18.2.0/24

Customer DMZ (future): 10.0.2.0/24
  Isolated, firewall-regulated
```

### 2.3 KPI Framework

| KPI | Definition | Current | Target (3mo) | Target (12mo) |
|-----|-----------|---------|-------------|---------------|
| MTTR | Mean Time to Recovery | Unknown | < 4h | < 1h |
| Backup Success Rate | % successful / planned | Unknown | > 95% | > 99.5% |
| Restore Test Frequency | Tests per quarter | 0 | >= 1 | >= 1 (quarterly) |
| VM Deployment Time | Template clone to functional VM | ~15-30 min | < 15 min | < 5 min |
| Infra Drift Incidents | Unexpected config changes / quarter | Unknown | Start tracking | < 2 |
| Security Event Detection Latency | Time until event detected | Unknown (likely days) | < 24h | < 1h |
| Uptime | AI-VM / jbot stack availability | Not measured | > 95% | > 99% |
| GPU Inference Latency | P95 for 7B model | Not measured | Establish baseline | < 2s P95 |
| Pilot Customers | Active pilot customers | 0 | >= 1 | >= 3 |
| MRR | Monthly Recurring Revenue | 0 EUR | > 0 EUR | > 1,500 EUR |

---

## 3. Integration

### 3.1 Technical Integration

**GPU Resource Planning**

Current: Single GPU (RX 6800 XT, 16 GB VRAM), exclusive to Linux AI-VM via VFIO passthrough.

| Scenario | VRAM Need | Realistic? |
|----------|-----------|------------|
| Ollama (7B model, Q4) | ~4-5 GB | Yes |
| Ollama (13B model, Q4) | ~8-9 GB | Yes |
| Ollama (70B model, Q4) | ~35+ GB | No |
| 2x concurrent 7B inference | ~10 GB | Possible but latency drops |
| Ollama + AI training | ~14+ GB | Borderline |

**AI Workload Request Flow**

```
Client -> Traefik (TLS) -> jbot-api (FastAPI)
                               |
                               +-> Qdrant (vector search, RAG context)
                               +-> Ollama (LLM inference, ROCm/GPU)
                               +-> Redis (cache, rate limiting)
                               +-> Response back via Traefik
```

Missing elements: retry logic, circuit breaker, request queue, model routing.

### 3.2 Organizational Integration

**Governance Documentation Status**

| Document | Exists? | Priority |
|----------|---------|----------|
| Architecture diagram | Partially (phase plan notes) | High |
| Runbooks (host restart, VM recovery, stack restart) | No | High |
| Incident response plan | No | High |
| Root account policy | Implicit (in masterprompt) | Medium — formalize |
| Backup policy (incl. restore procedure) | No (formalized) | High |
| Network diagram | No | Medium |
| Change log | Partially (Git/scripts) | Medium |
| DSGVO documentation (VVT, TOMs) | No | Critical |
| AI Act documentation | No | High |

**Bus Factor: 1** — Greatest non-technical risk.

Mitigations (by effort):
1. **Immediate:** Password safe with all credentials (KeePass/Bitwarden)
2. **Short-term:** Runbooks for critical recovery scenarios
3. **Medium-term:** Technical co-founder or freelance sysadmin
4. **Long-term:** Automation reduces dependency on personal knowledge

### 3.3 Process Integration

**Change Control Categories**

| Category | Action | Documentation |
|----------|--------|--------------|
| STANDARD | Routine (updates, model changes) | Snapshot + execute + document |
| NORMAL | Infrastructure change (network, storage, firewall) | Snapshot + plan + validation |
| EMERGENCY | Security incident | Act immediately, document after |

**Rollback Strategies**

```
Level 1 (Docker):  docker compose down -> previous image tags -> up
Level 2 (VM):      Proxmox snapshot rollback (seconds)
Level 3 (Host):    vzdump restore (minutes to hours)
Level 4 (Disaster): Reinstall from documented playbook + offsite backup
```

**Incident Severity Levels**

| Level | Description | Response Time | Target MTTR |
|-------|-------------|---------------|-------------|
| SEV1 | Total AI-VM outage or data loss | Immediate | < 2h |
| SEV2 | Critical service down (Ollama, jbot-api) | < 1h | < 4h |
| SEV3 | Degraded performance, non-critical service down | < 4h | < 24h |
| SEV4 | Log anomaly, no impact | Next business day | — |

---

## 4. Implementation

See [90-Day Tactical Plan](roadmap-90day.md) for detailed execution steps.

### 4.1 Long-Term Vision (12+ Months)

**Hybrid Cloud Architecture**

```
On-Prem (FitnaAI Core):
  GPU inference (latency-sensitive, data-sovereign)
  Vector DB (customer data)
  Agent logic (jbot-api)

EU Cloud (optional, customer-dependent):
  Frontend / Dashboard
  API Gateway
  Burst inference (when local GPU saturated)
  Geo-redundant backup
```

**GPU Cluster Scaling Path**

| Phase | Hardware | Capability |
|-------|----------|------------|
| Current | 1x RX 6800 XT (16 GB) | 7B-13B models, single-tenant |
| +1 GPU | 2x GPU (32 GB total) | 13B-33B models, 2-3 concurrent sessions |
| Multi-Node | 2-3 nodes, 1-2 GPUs each | 33B+ models, multi-tenant, redundant |
| Enterprise | Dedicated GPU cluster | 70B+ models, production-grade |

**Monetization Options**

| Model | Description | Prerequisites |
|-------|-------------|---------------|
| SaaS | AI agents as service, monthly subscription | EU cloud infra, multi-tenant |
| On-Prem Bundle | Hardware + software + setup, then maintenance contract | Standardized hardware config |
| Managed AI | FitnaAI operates agents on customer infrastructure | Remote management capabilities |
| Consulting/Workshops | AI strategy + implementation for SMEs | Expertise + reference customers |
| API-as-a-Service | Access to local LLMs via API (DSGVO-compliant) | Robust infrastructure, SLAs |

**Recommendation:** Start with Consulting + Managed AI (lowest infrastructure requirement, fastest revenue). Scale to SaaS once platform is multi-tenant capable.

---

## 5. Critical Success Factors

### Top 5 Executive Priorities

| Priority | Key Actions | Success Metric |
|----------|------------|----------------|
| **Stability** | Restore test, offsite backup, monitoring + alerting, runbooks | MTTR < 4h, backup rate > 95%, 1+ restore drill/quarter |
| **Security** | Proxmox MFA, Samba hardening, auditd, API auth, backup encryption | Zero unprotected attack surfaces, detection < 24h |
| **Scalability** | ZFS vs LVM decision, second node plan, portable Docker stack | VM deploy < 15 min, documented scaling path |
| **Automation** | All configs in Git, automated backup validation, CI/CD pipeline | Drift incidents < 2/quarter, 100% configs in Git |
| **Knowledge Resilience** | Password safe, runbooks, architecture diagram, onboarding doc | Setup takeable in < 4h with runbooks |

### Key Decision Templates

**Decision 1: ZFS vs. LVM**
- Option A: Stay with LVM (no migration effort)
- Option B: ZFS on second node from start
- **Recommendation: Option B** — ZFS on new hardware, don't migrate current system

**Decision 2: Monitoring Stack**
- Option A: Prometheus + Grafana only (metrics)
- Option B: + Loki + AlertManager (full observability)
- **Recommendation: Option B** (phased: first metrics+alerts, then logs)

**Decision 3: First Pilot Customer Timing**
- Option A: Perfect infrastructure first
- Option B: DSGVO basics + API auth, then pilot
- **Recommendation: Option B** — DSGVO basics + API auth are minimum, then pilot with bounded scope

**Decision 4: GPU Strategy**
- Option A: AMD/ROCm only
- Option B: Evaluate NVIDIA for second node
- **Recommendation: AMD for existing node, evaluate NVIDIA for second node** (diversification reduces platform risk)

---

## Appendix

### A. RACI Matrix (Target State with Team)

| Activity | Ops | Security | Architecture | Product |
|----------|-----|----------|-------------|---------|
| Host Hardening | R,A | C | I | I |
| VM Provisioning | R,A | C | C | I |
| Docker Stack Deployment | R,A | I | C | C |
| Monitoring & Alerting | R,A | C | I | I |
| Backup & Restore | R,A | C | I | I |
| Security Audit | C | R,A | I | I |
| DSGVO Documentation | C | R,A | I | C |
| AI Act Classification | I | C | R,A | C |
| Architecture Decisions | C | C | R,A | C |
| Customer Onboarding | C | I | I | R,A |

### B. Infrastructure Maturity Classification

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Provisioning | 3/5 | Cloud-Init templates, deterministic root deployments. Missing: versioning, automated testing |
| Backup & Recovery | 2/5 | vzdump + cron present, snapshot strategy defined. No restore test, no offsite, no encryption |
| Monitoring | 1.5/5 | Prometheus/Grafana defined but not operational. No alerting, no log management |
| Network & Segmentation | 2.5/5 | Docker network isolation good (internal:true). Host/VM: flat /16, no inter-VM firewall rules |
| Security Hardening | 2/5 | Basic (firewall, Fail2Ban, SSH). No MFA, no IDS, no encryption at rest, no audit trail |
| Documentation & Governance | 1.5/5 | Phase plan and validate-phase4.sh exist. No runbooks, policies, architecture diagram |
| Automation | 2.5/5 | Scripts and docker compose present. No CI/CD, no automated tests, no policy-as-code |
| **OVERALL** | **2.1/5** | Advanced homelab with solid foundation, significant gaps in observability, security, compliance, documentation |

### C. AI Readiness Score

**Technical: 6/10**

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| GPU Inference | 7 | ROCm works, Ollama runs, 16 GB VRAM for 7B-13B |
| Vector DB Integration | 7 | Qdrant operational, RAG pipeline possible |
| API Layer | 6 | FastAPI backend ready, no AuthN/AuthZ |
| Multi-Model Management | 4 | Ollama can load models, no scheduling |
| AI Observability | 3 | No AI-specific metrics |
| Scalability | 3 | Single-GPU, single-node, no auto-scaling |
| Robustness | 5 | Snapshot recovery, no circuit breaker |
| Container Security | 4 | Docker isolation present, no Seccomp/AppArmor profiles |

**Commercial: 2/10**

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Pilot Customers | 1 | None |
| SLA Capability | 1 | No SLAs, no uptime tracking |
| Pricing | 1 | Not defined |
| DSGVO Compliance | 1 | No documentation |
| AI Act Compliance | 1 | Not classified |
| Onboarding Process | 1 | Not defined |
| Multi-Tenant Capability | 2 | Docker isolation as basis, not designed for multi-tenant |
| Market Differentiation | 5 | Data sovereignty + local inference is real USP |
