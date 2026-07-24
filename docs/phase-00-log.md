# Phase 0 Log — Foundation

**Date:** 2026-07-24 · **Planned:** Week 1 · **Actual:** 1 day

## Objective
Working environment, version-controlled repo, written charter.
No Fabric build work — deliberately.

## Delivered
| # | Item | Evidence |
|---|---|---|
| 1 | Own Entra tenant | urbanflowlaboutlook.onmicrosoft.com |
| 2 | Azure subscription (free tier, Active) | Billing on personal MSA |
| 3 | Native admin identity, Global Administrator | admin@urbanflowlaboutlook.onmicrosoft.com |
| 4 | Fabric free licence provisioned | Self-service sign-up |
| 5 | Toolchain | Git 2.55, Python 3.12.10, VS Code 1.130 |
| 6 | Public repo + folder structure | urbanflow-fabric-platform |
| 7 | Project charter | docs/00-charter.md |
| 8 | Traceability matrix | docs/01-traceability.md |

**Fabric trial capacity: NOT activated.** 60-day clock reserved for Phase 6.

## Blockers and resolutions

### B1 — Only client tenants available
Accessible Fabric environments belonged to clients, not to me.
Using them would have consumed client capacity, appeared in their
audit logs under a shared service account, and in one case burned a
one-time trial capacity the client may need.

**Resolution:** built an independent tenant. Cost $0.
**Principle:** portfolio work never touches client or employer tenants.

### B2 — Personal accounts cannot use Fabric
Fabric requires a work or school account; @outlook and @gmail are
rejected at sign-up.

**Resolution:** Azure sign-up with a personal email provisions a real
Entra tenant, which yields a work-style identity Fabric accepts.

### B3 — Microsoft 365 Developer Program no longer an option
The free E5 sandbox now requires a Visual Studio Professional or
Enterprise subscription, or qualifying partner status.

**Resolution:** ruled out early rather than pursued. Time saved.

### B4 — AADSTS16000 authentication loop
Entra admin center repeatedly failed to issue a token, resolving
sign-in against the wrong tenant context ("Microsoft Services").
Root cause: multiple Microsoft sessions in one browser profile, plus
a GUID-named shadow directory with no provisioned portal apps.

**Resolution:** dedicated browser profile, session logout, and tenant
creation via Azure sign-up instead of the Entra portal.
**Rule adopted:** one browser profile = one Microsoft account.
**Cost:** roughly 45 minutes. Largest single time loss of the phase.

### B5 — Shell syntax mismatch
Directory-creation commands failed; cmd syntax was run in PowerShell.

**Resolution:** rewritten as PowerShell cmdlets.
**Note:** VS Code's integrated terminal is PowerShell by default.

### B6 — Python 3.12.13 ships no Windows installer
Latest 3.12 patch is source-only. 3.12.10 is the last release with
binary installers.

**Resolution:** installed 3.12.10.
**Why not 3.13:** PySpark and delta-rs wheel support is more reliable
on 3.12.

## Decisions taken
| Decision | Rationale | ADR |
|---|---|---|
| Independent tenant over employer/client | Ownership, admin access, portability | ADR-001 pending |
| Two accounts: MSA for billing, native for work | Licensing reliability; mirrors real separation of duties | ADR-001 pending |
| Delay Fabric trial to Phase 6 | 60-day clock is a scarce resource | ADR-002 pending |
| Local-first for Phases 1-3 | Removes cloud dependency from the critical path | ADR-002 pending |
| Repo is the portfolio, not the tenant | Survives trial expiry and account loss | — |

## Carried forward
- Budget alert on the Azure subscription — scope picker would not
  resolve the subscription; deferred, spending limit is on by default
- ADR-001 and ADR-002 to be written in Phase 1
- Screenshots for docs/img not yet captured systematically

## What I would do differently
Create the dedicated browser profile first. Every authentication
failure in this phase traced back to mixed sessions in one profile.

## Assessment
Phase 0 was planned as one week and took one day of build time.
The value was not the clicking — it was the tenant-ownership decision
and the discipline of not starting the trial clock early. Both are
constraints that shape every later phase.