# Security Architecture & Compliance (DSGVO / AI Act)

> Security deep dive, Zero Trust gap analysis, and EU compliance requirements
> for the FitnaAI platform. Covers DSGVO (GDPR) and EU AI Act obligations.

---

## 1. Zero Trust Gap Analysis

| Layer | Zero Trust Principle | Current State | Gap | Priority |
|-------|---------------------|---------------|-----|----------|
| **Host** | Identity-based access | root login without MFA | No MFA, no session recording | High |
| **Host** | Least privilege | Everything as root | Acceptable for single-op, but no audit | Medium |
| **Proxmox UI** | AuthN + AuthZ | Password login | No MFA | High |
| **VM** | Segmentation | VMs on same bridge network | No firewall rules between VMs | Medium |
| **Docker** | Network isolation | internal:true for backend | Good | — |
| **Docker** | Image integrity | Not verified | No image signing/pinning | Medium |
| **API (jbot)** | AuthN/AuthZ | Not implemented | Open API | High |
| **Data** | Encryption at rest | Not present | Cleartext data on SSD | High |
| **Data** | Encryption in transit | TLS via Traefik | Good (external), unclear (internal) | Medium |
| **Backup** | Encryption | Presumably unencrypted | — | High |

---

## 2. Root Account Governance & Key Management

**Current state:**
- root is used directly
- SSH keys presumably present (Fail2Ban + SSH hardening implies this)
- No central key management
- No key rotation process

**Required actions:**

1. **SSH key inventory:** Which keys are authorized? Where are private keys stored?
2. **Key rotation policy:** Annually, or immediately on suspected compromise
3. **Passphrase requirement:** All SSH private keys MUST be passphrase-protected
4. **authorized_keys audit:** Regular check that only known keys are present
5. **Long-term:** Hardware tokens (YubiKey) for SSH and Proxmox UI

---

## 3. SSH & Firewall Hardening

**Expected SSH config (to validate on hosts):**

```
# /etc/ssh/sshd_config (Host)
PermitRootLogin prohibit-password    # Key-based only
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
AllowUsers root                      # Only root (single-op)
Protocol 2
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

**Recommended firewall rules (Proxmox Firewall):**

```
# Inbound (Host)
ACCEPT  tcp  22      source: management-net only (SSH)
ACCEPT  tcp  8006    source: management-net only (Proxmox UI)
DROP    all          default deny

# Inbound (AI-VM)
ACCEPT  tcp  80,443  (Traefik)
ACCEPT  tcp  22      source: management-net only (SSH)
DROP    all          default deny

# Inter-VM
DROP    all          default deny, explicit exceptions only
```

---

## 4. Intrusion Detection Options

| Level | Timeframe | Solution | Effort |
|-------|-----------|----------|--------|
| Minimal | Immediate | Extend Fail2Ban rules (Proxmox UI, Traefik 4xx floods) | Low |
| Lightweight | Month 1-2 | OSSEC/Wazuh agent on host + AI-VM (log-based IDS) | Medium |
| Medium-term | Month 3-6 | Suricata on host bridge (network IDS) | Medium |
| Long-term | Month 6+ | SIEM integration (Wazuh Server or Grafana-based) | High |

**Recommendation:** Level 1 immediately, Level 2 during observability phase.

---

## 5. Encryption Requirements

| Area | Current | Target | Action |
|------|---------|--------|--------|
| SSD (disk) | Unencrypted | LUKS or ZFS encryption | At next reinstall or second node |
| VM disks | Unencrypted | LUKS in VM | Implement in AI-VM (especially for customer data) |
| Backups | Unencrypted | AES-256 (vzdump encryption) | Activate immediately |
| Network (external) | TLS via Traefik | TLS 1.3, HSTS | Review Traefik config |
| Network (internal) | Cleartext | mTLS between containers (long-term) | Phase 5 |
| Samba | SMB3 + transport encryption | SMB3-only, signing required | Check and activate now |

---

## 6. DSGVO (GDPR) Compliance

### 6.1 Personal Data Mapping

```
Storage locations of personal data:

Samba Share /home/fitna
  Risk: HIGH
  Data types: Project data, potentially customer documents, emails
  Current protection: Filesystem permissions (presumably)
  Required: Encryption, ACLs, audit log, access restrictions

Qdrant Collections
  Risk: MEDIUM to HIGH
  Data types: Vector embeddings of text (may contain PII)
    NOTE: Embeddings not trivially reversible, but
    metadata/payloads in Qdrant can contain cleartext PII
  Current protection: Docker network isolation (internal:true)
  Required: API key/AuthN, encryption at rest, backup

jbot-api Logs
  Risk: MEDIUM
  Data types: User queries, conversations (potentially PII)
  Current protection: Container-internal
  Required: Log rotation, retention period, PII filtering

Traefik Access Logs
  Risk: LOW to MEDIUM
  Data types: IP addresses, URLs, timestamps
  Current protection: Container-internal
  Required: Retention period (max 7-30 days), IP anonymization

Prometheus/Grafana Metrics
  Risk: LOW
  Data types: Aggregated metrics (normally no PII)
  Required: Standard access protection sufficient

Redis
  Risk: MEDIUM
  Data types: Cache data, session data (potentially PII)
  Current protection: Docker network isolation
  Required: AUTH password, TTL for sensitive data
```

### 6.2 Required DSGVO Documents

| Document | DSGVO Article | Status | Priority |
|----------|--------------|--------|----------|
| **Verzeichnis der Verarbeitungstaetigkeiten (VVT)** | Art. 30 | Not present | **CRITICAL** |
| **TOM Documentation** | Art. 32 | Not present | **CRITICAL** |
| **AV Contract Template** | Art. 28 | Not present | **CRITICAL** (before customer ops) |
| **Data Protection Information** | Art. 13/14 | Not present | High |
| **Deletion & Retention Concept** | Art. 17 | Not present | High |
| **Data Subject Rights Process** | Art. 15-22 | Not present | High |
| **Data Protection Impact Assessment (DSFA)** | Art. 35 | Not present | Medium (before high-risk use cases) |

### 6.3 VVT Content Requirements

The Verzeichnis der Verarbeitungstaetigkeiten must contain per processing activity:
- Purpose of processing
- Legal basis
- Categories of affected persons
- Categories of personal data
- Recipients
- Deletion periods
- Technical and organizational measures (TOMs)

### 6.4 Required TOMs (Art. 32 DSGVO)

**Technical measures:**
- Access control (ACLs, RBAC, SSH key policy)
- Encryption (at rest & in transit)
- Logging & monitoring
- Backup & restore processes (including test)
- Network segmentation
- Container isolation

**Organizational measures:**
- Security policies
- Change management process
- Incident response plan
- Regular audits
- Training/awareness (when team grows)

### 6.5 Log Retention Policy (DSGVO-compliant)

| Log Type | Max Retention | Justification |
|----------|-------------|---------------|
| Traefik access logs | 30 days | Legitimate interest (security), IP = personal data |
| jbot-api request logs | 30 days | Service operation, PII minimization |
| Security logs (Fail2Ban, auditd) | 90 days | Security incident investigation |
| Audit logs | 365 days | Compliance documentation |
| AI decision logs | 6 months minimum | AI Act requirement |
| Backup logs | 90 days | Operational necessity |

---

## 7. EU AI Act Compliance

### 7.1 Risk Classification of Typical FitnaAI Agents

| Use Case | Risk Class | Rationale | Obligations |
|----------|-----------|-----------|-------------|
| **Office Automation** (email summaries, document search) | **Minimal / Limited** | No decisions with legal effect, no profiling | Transparency (user knows AI is involved), logging |
| **Knowledge Agent** (RAG over company data, Q&A) | **Limited** | Information provision, no autonomous decisions | Transparency, technical documentation, logging |
| **SME Assistant** (offer creation, customer analysis) | **Limited**, potentially **High Risk** for creditworthiness/HR | Depends on concrete use — decisions about natural persons -> High Risk | High Risk: conformity assessment, risk management, human oversight, quality management, logging |
| **Customer Communication Bot** | **Limited** | Chatbot transparency obligation (Art. 50 AI Act) | Transparency labeling, logging |

### 7.2 FitnaAI as "Deployer" under AI Act

As a company deploying AI systems for customers (on-prem), FitnaAI is likely a "Deployer" (Betreiber). Obligations:

1. **Transparency:** Inform users that AI is in use
2. **Monitoring:** Monitor AI system in operation (logging, anomaly detection)
3. **Human Oversight:** For high-risk systems: enable human review
4. **Documentation:** Technical documentation of system, data flows, inference pipeline
5. **Risk Management:** Regular assessment of AI system risks

### 7.3 Required AI Act Artifacts

| Artifact | Status | Priority |
|----------|--------|----------|
| Risk classification per use case | Not present | High |
| Risk management process (high-risk) | Not present | Medium (only for high-risk use cases) |
| Logging & monitoring (AI decisions) | Not present | High |
| Technical documentation (data flows, models, pipeline) | Not present | High |
| Human oversight mechanisms | Not present | Medium |
| Transparency labeling (chatbot, AI-generated content) | Not present | High |

### 7.4 AI Act Implementation Checklist

For each deployed agent/use case:

- [ ] Risk class determined and documented
- [ ] If Limited Risk:
  - [ ] Transparency notice implemented (user informed of AI interaction)
  - [ ] Logging of AI interactions enabled
  - [ ] Technical documentation complete
- [ ] If High Risk (additional):
  - [ ] Conformity assessment performed
  - [ ] Risk management process documented
  - [ ] Human oversight mechanism implemented
  - [ ] Quality management system in place
  - [ ] Automatic logging with audit trail
  - [ ] Data governance measures documented

---

## 8. Governance & Audit Schedule

### 8.1 Monthly Review (1h)

- Security log review (Fail2Ban, auditd, Traefik anomalies)
- Backup status check (all backups successful? rotation correct?)
- Capacity review (disk, RAM, GPU utilization)
- Open risks from risk register
- Change log review
- Document decisions

### 8.2 Quarterly Review (2h)

- Restore drill
- Security hardening check (SSH keys, firewall rules, updates)
- Update KPIs
- Roadmap review
- Compliance check (DSGVO, AI Act)
- Update risk register

### 8.3 Change Approval Thresholds

| Change Type | Approval | Documentation |
|-------------|----------|---------------|
| Container update (minor) | Self-approve | Changelog entry |
| OS update (VM) | Self-approve + snapshot | Changelog entry |
| Proxmox host update | Snapshot + planned maintenance window | Detailed changelog |
| Network change | Snapshot + plan + validation | Detailed changelog + network diagram update |
| Storage change | Backup + snapshot + plan | Detailed changelog |
| New VM/service | Architecture review (self) | Architecture diagram update |
| GPU passthrough change | Snapshot (protect `rocm-working`!) + dedicated test window | Detailed changelog |

### 8.4 Audit Frequency

| Audit | Frequency | Responsible |
|-------|-----------|-------------|
| Backup validation (automated) | Daily (cron check) | Automated + Jonas |
| Restore drill | Quarterly | Jonas |
| SSH key audit | Quarterly | Jonas |
| Firewall rule review | Quarterly | Jonas |
| DSGVO compliance check | Semi-annually | Jonas (+ external DPO if budget allows) |
| AI Act review | Semi-annually | Jonas |
| Full security audit | Annually | External (when budget available) |
