# ADR-002: Infrastructure Topology Must Be Resolved Before Phase 6

**Status:** Proposed (BLOCKED — waiting for operator answers)
**Date:** 2026-02-12
**Decision makers:** Projektleitung + Operator

## Context

Screenshots from the Proxmox mobile app reveal a more complex topology than originally assumed:

- **Two subnets**: 192.168.16.0/24 and 192.168.17.0/24
- **At least 3 Proxmox nodes**: pve (16.2), pve (16.7), pve-ryzen (17.1/17.16)
- **Dual IP on pve-ryzen**: 192.168.17.1 and 192.168.17.16

This is no longer a simple 2-host setup. It may be a cluster-in-preparation.

## Blockers (must be answered)

### BLOCKER-1: Is 192.168.16.7 a Proxmox node?
- **If YES** → 3-node cluster, need quorum strategy, corosync network, fencing
- **If NO** → Documentation is inconsistent, remove from inventory

### BLOCKER-2: pve-ryzen NIC topology
- **Two physical NICs?** → Proper VLAN separation (management vs production). Professional.
- **One NIC, two IPs?** → Unnecessary complexity, security risk. Simplify.

### BLOCKER-3: Production compute host
- Where does fitnaai run in production?
  - pve (16.2) — has RX 6800 XT but is the Windows workstation
  - pve (16.7) — unknown role
  - pve-ryzen (17.1) — has GTX 1080, already running Docker/Debian

### BLOCKER-4: Public API intent
- Is fitnaai meant to be publicly accessible (via VPS, reverse proxy)?
- Or internal-only within the homelab/startup network?

## Decision

**FEATURE FREEZE until all 4 blockers are resolved.**

No new development on:
- Cluster configuration scripts
- Production deployment scripts
- Network topology changes
- fitnaai production hardening

Development that CAN continue:
- fitnaai core API logic (business logic, endpoints)
- Unit tests
- Local development workflow

## Expected Answers Format

```
BLOCKER-1 (16.7 node):    Yes/No + role
BLOCKER-2 (ryzen NICs):   1 NIC / 2 NICs + purpose
BLOCKER-3 (prod host):    16.2 / 16.7 / ryzen
BLOCKER-4 (public API):   Yes/No + timeline
```
