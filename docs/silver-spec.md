# Silver Layer Specification

## Purpose
Silver is the investigation layer. Every Bronze row survives in some form,
fully typed, with its data-quality history attached. Nothing is deleted.

## Two tables

### silver_trip
Every Bronze row that is physically possible. Carries a dq_flags array
recording every rule the row tripped. An empty array means clean.

### silver_trip_quarantine
Every physically impossible row, with the failing rule attached.
These are retained, not deleted, so the exclusion is auditable.

**Invariant:** silver_trip + silver_trip_quarantine = Bronze row count.

## dq_flags — the flag catalogue

This is the contract. Each flag is a string constant.

| Flag | Rule | Rows (2024 Q1) | Disposition |
|---|---|---:|---|
| NULL_BLOCK | passenger_count IS NULL | 751,962 | flag, keep |
| NEGATIVE_FARE | fare_amount < 0 | 136,567 | flag, keep |
| NEGATIVE_TOTAL | total_amount < 0 | 115,895 | flag, keep |
| ZERO_DISTANCE | trip_distance = 0 | 215,764 | flag, keep, exclude from distance KPIs |
| ZERO_PASSENGERS | passenger_count = 0 | 105,931 | flag, keep, map to unknown |
| UNKNOWN_VENDOR | VendorID NOT IN (1,2) | 720 | flag, keep |
| OUT_OF_PERIOD | pickup not in declared window | 21 | flag, keep, partition by actual date |
| IMPOSSIBLE_DURATION | dropoff <= pickup | 2,801 | **quarantine** |
| EXCESSIVE_DURATION | duration > 12h | 4,907 | **quarantine** |
| IMPOSSIBLE_DISTANCE | trip_distance > 200 mi | 170 | **quarantine** |

Quarantine rules are the routing key: a row tripping any of the three
quarantine rules goes to silver_trip_quarantine and never to silver_trip.
The seven non-quarantine flags are recorded on silver_trip rows.

A row may carry multiple flags. Counts above overlap and do not sum.

## Identity

TLC data ships no unique key. We derive a deterministic one.

**trip_id** = MD5 hash of the business-defining columns:
tpep_pickup_datetime, tpep_dropoff_datetime, PULocationID,
DOLocationID, trip_distance, fare_amount, VendorID.

Properties:
- Deterministic: the same trip always hashes to the same id, on every
  run and in every engine. This is what makes incremental load safe and
  invariant #2 (no id in both tables) checkable.
- Not a business guarantee of uniqueness: if two genuinely identical
  trips exist, they collide by design. Profiling found 1 probable
  duplicate in 9.55M rows, so this is negligible and, arguably, correct —
  a true duplicate should collapse.

The hash uses the same columns as the Phase 1 duplicate check, so the
two are consistent.

## Type contract

| Column | Bronze | Silver | Reason |
|---|---|---|---|
| VendorID | INTEGER | INTEGER | |
| tpep_pickup_datetime | TIMESTAMP | TIMESTAMP | |
| tpep_dropoff_datetime | TIMESTAMP | TIMESTAMP | |
| passenger_count | BIGINT | INTEGER, 0 → NULL | 0 means "not entered", not zero people |
| trip_distance | DOUBLE | DECIMAL(10,2) | |
| RatecodeID | BIGINT | INTEGER | |
| store_and_fwd_flag | VARCHAR | BOOLEAN | Y/N → true/false |
| PULocationID | INTEGER | INTEGER | |
| DOLocationID | INTEGER | INTEGER | |
| payment_type | BIGINT | INTEGER | |
| fare_amount | DOUBLE | DECIMAL(10,2) | Money as DECIMAL — DOUBLE sums drift |
| total_amount | DOUBLE | DECIMAL(10,2) | Same |
| (all other money columns) | DOUBLE | DECIMAL(10,2) | Same |
| dq_flags | — | ARRAY<VARCHAR> | Never NULL; empty array when clean |
| partition_date | — | DATE | Derived from pickup, never filename |
| trip_duration_min | — | INTEGER | Derived; NULL if duration invalid |
| is_billable | — | BOOLEAN | total_amount > 0 AND trip_distance > 0 |

## Derived columns

- **partition_date** = CAST(tpep_pickup_datetime AS DATE)
- **trip_duration_min** = minutes between pickup and dropoff;
  NULL when the row is quarantined for a duration rule
- **is_billable** = a convenience flag so distance/revenue KPIs can
  exclude zero-distance and non-positive-total rows without repeating
  the logic in every measure

## Invariants asserted every run

1. silver_trip.count + silver_trip_quarantine.count = source.count
2. No trip_id appears in both tables
3. Every quarantined row carries at least one quarantine flag
4. dq_flags is never NULL
5. Every partition_date is derived from pickup, and all quarantined
   OUT_OF_PERIOD rows are still routed by their true date
6. No money column is NULL where Bronze had a value

## dq_results — run telemetry

Each run appends one row per (run_date, partition_month, flag) with a count,
so the null-block trend and every other rule stays visible over time rather
than being rediscovered. This is what makes the Phase 1 finding — the rising
null-block rate — a monitored metric instead of a one-off observation.

## What changes when this ports to Fabric (Phase 6a)

- MERGE INTO replaces table recreation for incremental loads
- Delta partitioning replaces DuckDB's file layout
- date_diff argument order differs between DuckDB and Spark SQL
- ARRAY<VARCHAR> is native in Lakehouse Delta; Gold flattens to booleans
  for the Warehouse
The SQL logic itself is intended to transfer with minimal change.