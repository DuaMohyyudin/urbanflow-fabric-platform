# ADR-003: Flag and quarantine rather than delete

**Status:** Accepted · **Date:** 2026-07-24

## Context
Profiling found ~1.1M rows failing at least one plausibility check, of
which 7,878 are physically impossible.

## Decision
Every row carries a `dq_flag`. Impossible rows go to
`silver_trip_quarantine` with the failing rule attached. Nothing is
deleted.

## Consequences
- Positive: 136,567 negative-fare rows are retained. They are refunds,
  and deleting them would understate cost of revenue.
- Positive: exclusions are auditable and reversible.
- Negative: downstream measures must apply exclusions explicitly.
  A careless DAX measure will include quarantined behaviour.
- Negative: Silver carries rows Gold will never use, costing storage.