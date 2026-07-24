# ADR-002: Defer Fabric to Phase 6, build Phases 1-5 locally

**Status:** Accepted
**Date:** 2026-07-24
**Amended:** 2026-07-24

## Context

Fabric trial capacity is 64 CU for 60 days, granted once per tenant and
non-renewable. Once started, the clock runs whether or not the capacity is
in use.

Phases 1 through 5 are ingestion, cleansing, dimensional modelling, semantic
modelling and report design. None of these strictly require Fabric compute to
design and validate:

- Profiling and transformation logic can be written and tested in ANSI SQL
  against Parquet files locally
- Power BI Desktop is free and runs the full semantic model, DAX and report
  authoring experience without any service licence
- Star schema design is a modelling exercise, not a compute exercise

The capabilities that genuinely require Fabric are concentrated later:
Direct Lake, Eventstream, Eventhouse, Activator, deployment pipelines,
capacity metrics, OneLake shortcuts and workspace governance.

## Decision

Profile and prototype Phases 1-5 locally using DuckDB and Python for the
data layers, and Power BI Desktop for the semantic layer and reports.

Activate the Fabric trial at Phase 6, when the Fabric-specific capabilities
become unavoidable.

## Consequences

**Positive**

- The 60-day window covers the phases that actually consume it, rather than
  expiring during work that did not need it.
- Phase 1 cost $0 and produced ANSI SQL that transfers to the Fabric
  Warehouse and to Spark SQL with minimal change.
- Local iteration is faster than cloud iteration, so the exploratory work
  where the shape of the problem is still unknown happens where the feedback
  loop is shortest.

**Negative**

- The Bronze ingestion originally planned for Phase 1 — metadata-driven Data
  Factory pipeline, control table, ForEach loop, watermark-based incremental
  load, Dataflow Gen2 — is **deferred, not delivered**. It is required for
  DP-700 and must be built once capacity is live. The traceability matrix
  reflects this as in-progress, not complete.
- The local Python download script is throwaway. It will be replaced by a
  Copy activity, not ported. What transfers is the idempotence principle,
  which reappears as a watermark table.
- DuckDB is not Spark. Join skew, small-file behaviour, partition pruning and
  V-Order effects will differ and must be re-measured on Fabric. Any
  performance claim made locally is provisional.
- Delta-specific operations — `MERGE INTO`, `OPTIMIZE`, `VACUUM`, time travel
  — cannot be exercised locally and are unproven until Phase 6a.

## Amendment — 2026-07-24

Phase 6 as originally scoped absorbs the entire deferred Fabric workload plus
the real-time layer. That is too much for a single phase inside a 60-day
window, and the risk is that something is finished badly rather than finished.

Phase 6 is therefore split:

| Phase | Scope | Target days |
|---|---|---:|
| 6a — Migration | Trial activation, Lakehouse and Warehouse, metadata-driven Bronze pipeline with control table, ForEach and watermark, Silver notebooks ported, Gold star schema rebuilt on Delta | 1-18 |
| 6b — Real-time | Event producer, Eventstream, Eventhouse, update policies, materialized views, retention and caching policy, KQL dashboard, Activator alerting | 19-32 |
| 6c — Semantic layer on Fabric | Direct Lake model, RLS, reports republished, performance tuning and measurement | 33-42 |
| 7 — AI | Forecasting, RAG copilot, NL-to-query agent, evaluation harness | 43-52 |
| 8 — Governance and CI/CD | Git integration, deployment pipelines, sensitivity labels, monitoring, cost analysis, runbook | 53-60 |

**This makes Phases 2-5 load-bearing.** They must be complete enough that
Phase 6 is a port rather than a redesign: every Silver rule, every surrogate
key strategy, every DAX measure and every report layout should be final
before the trial clock starts.

The schedule gain from completing Phases 0 and 1 in one day is therefore
allocated to depth in Phases 2-5, not to starting Phase 6 early.

## Review trigger

Revisit this decision if any of the following occur:

- A Phase 2-5 design question cannot be answered without Fabric-specific
  behaviour, and the answer materially changes the model
- Microsoft changes trial terms in a way that affects the 60-day assumption
- Phases 2-5 are complete and the port is estimated at under 10 days, in
  which case Phase 6a can absorb more of Phase 6b