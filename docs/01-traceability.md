# Charter Traceability

Every charter commitment maps to a phase, an artefact, and evidence.
No row gets deleted. Scope changes get an ADR reference, not silence.

**Last updated:** 2026-07-24 (end of Phase 1)

## Status legend

| Status | Meaning |
|---|---|
| Not started | No work done |
| In progress | Partially delivered, or delivered in prototype form only |
| Deferred | Consciously moved to a later phase, with an ADR explaining why |
| Complete | Delivered and evidenced in the repo |

---

## Matrix

| # | Charter commitment | Phase | Artefact | Status | Evidence / ADR |
|---|---|---|---|---|---|
| 1 | KPI: revenue per vehicle hour | 4 | DAX measure | Not started | |
| 2 | KPI: idle time % | 4 | DAX measure | Not started | |
| 3 | KPI: cancellation rate by zone | 6b | KQL + DAX measure | Not started | |
| 4 | KPI: forecast MAPE beats seasonal-naive | 7 | `ai/forecast.ipynb` | Not started | |
| 5 | Finance: P&L by zone and month, daily refresh | 5 | Exec P&L report | Not started | |
| 6 | Ops: where are vehicles idle right now | 6b | Real-time dashboard | Not started | |
| 7 | Exec: plain-English questions | 7 | NL-to-query agent | Not started | |
| 8 | TLC trip records ingested | 1 → 6a | Bronze layer | **In progress** | Profiled locally, `notebooks/01_profile_bronze.ipynb`. Metadata-driven pipeline, control table, ForEach and watermark deferred to 6a — **ADR-002** |
| 9 | Zone lookup ingested | 2 → 6a | `dim_zone` (SCD2) | **In progress** | Raw file landed and referential integrity verified (0 orphans). SCD2 build pending Phase 3 — **ADR-002** |
| 10 | Weather ingested | 2 → 6a | `silver_weather_hourly` | Not started | Open-Meteo, not yet pulled |
| 11 | Simulated event stream | 6b | `streaming/producer.py` | Not started | |
| 12 | End-to-end refresh under 15 min | 8 | Measured and documented | Not started | Any local timing is provisional — **ADR-002** |
| 13 | All artefacts version-controlled | 0-9 | This repo | **In progress** | Public repo, 6 documents and 1 notebook committed |
| 14 | Deployable via pipeline | 8 | Deployment pipeline Dev→Test→Prod | Not started | Requires capacity — **ADR-002** |
| 15 | Public data only, no client or employer data | 0-9 | Ongoing discipline | **Holding** | Independent tenant built specifically to guarantee this — **ADR-001** |
| 16 | Total budget under $60 | 0-9 | Cost tracking | **On track** | $0 spent to end of Phase 1 — **ADR-002** |

---

## Additional commitments adopted after the charter

These were not in the original charter but became commitments during
Phase 1 and are tracked here so they cannot quietly disappear.

| # | Commitment | Phase | Status | Evidence / ADR |
|---|---|---|---|---|
| 17 | Nothing silently dropped: every row flagged or quarantined | 2 | Not started | **ADR-003** |
| 18 | Per-month null-block rate emitted to `dq_results` every run | 2 | Not started | `docs/data-quality.md` §4 |
| 19 | Partition by pickup date, never by filename | 2 | Not started | `docs/data-quality.md` §5 |
| 20 | Distance measures use median, not mean | 4 | Not started | `docs/data-quality.md` §4 |
| 21 | Bronze tolerates additive schema drift (`cbd_congestion_fee`, 2025+) | 6a | Not started | `docs/data-quality.md` §1 |
| 22 | Phase 6 split into 6a / 6b / 6c to fit the 60-day window | 6 | Accepted | **ADR-002 amendment** |

---

## Deferred items register

Anything moved out of its planned phase appears here until it is delivered.

| Item | Planned | Now | Reason | ADR |
|---|---|---|---|---|
| Metadata-driven Data Factory pipeline | 1 | 6a | Requires Fabric capacity; trial clock reserved | ADR-002 |
| Control table + ForEach ingestion loop | 1 | 6a | Same | ADR-002 |
| Watermark-based incremental load | 1 | 6a | Same | ADR-002 |
| Dataflow Gen2 for weather and zones | 1 | 6a | Same | ADR-002 |
| Azure budget alert | 0 | Any | Scope picker would not resolve the subscription; spending limit is on by default, so risk is low | — |

## Review cadence

This matrix is updated at the end of every phase. A phase is not closed
until its rows here are accurate.