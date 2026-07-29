# Phase 2 Log — Silver Layer

**Date:** 2026-07-29 · **Planned:** Week 3 · **Cost incurred:** $0

## Objective

Turn the Bronze findings into a cleansed, typed Silver layer where every rule
is enforced by an assertion that runs on every build. Nothing dropped
silently; every exclusion auditable.

## Delivered

| # | Item | Evidence |
|---|---|---|
| 1 | Typed Silver build | notebooks/02_silver_build.ipynb |
| 2 | Portable SQL for the Fabric port | sql/silver_build.sql |
| 3 | silver_trip with dq_flags array | 9,546,890 rows |
| 4 | silver_trip_quarantine with failing rule | 7,887 rows |
| 5 | dq_results run telemetry | per-month, per-flag |
| 6 | Seven invariants, all passing | Cell 5 of the notebook |
| 7 | ADR-004 duplicate collapse | docs/adr/adr-004-duplicate-collapse.md |
| 8 | Q12 correction | docs/data-quality.md section 5 |

## Row disposition

| Bucket | Rows |
|---|---:|
| Source | 9,554,778 |
| Clean (silver_trip) | 9,546,890 |
| Quarantined | 7,887 |
| Duplicate collapsed | 1 |
| **Conserved total** | **9,554,778** |

## Three problems found and fixed during the build

The build was not clean on the first pass. Each of these was caught by a
check, not by luck.

**1. NULL_BLOCK inflation.** Flags were first computed after mapping
passenger_count 0 to NULL, so NULL_BLOCK absorbed the ZERO_PASSENGERS rows
and read ~857k instead of ~751k. Fixed by preserving a raw passenger column
and computing every flag against the source value. Lesson: flag the source,
not the cleaned column.

**2. 333 refund pairs collapsed.** The first trip_id hash excluded
total_amount, so a +N charge and its -N reversal hashed identically and were
treated as one row. They are distinct financial transactions. Fixed by adding
signed total_amount and payment_type to the hash. Collisions fell from 333 to 1.

**3. One genuine duplicate.** The remaining collision was two byte-identical
rows — a real duplicate at source. Collapsed via QUALIFY ROW_NUMBER (ADR-004),
and the conservation invariant updated to account for it explicitly.

## Design decisions

| Decision | Rationale | Reference |
|---|---|---|
| dq_flags as an array in Silver | Extensible; a row shows every rule it tripped | silver-spec |
| Logic in SQL, not DataFrame API | Ports to Spark SQL in Phase 6a | ADR-002 |
| Money as DECIMAL(10,2) | Floating-point sums drift | silver-spec |
| Collapse exact duplicates only | A byte-identical row carries no information | ADR-004 |
| Keep refund pairs | Signed amount makes them distinct transactions | data-quality section 5 |
| dim_zone deferred to Phase 3 | SCD2 belongs with the Gold star schema | traceability row 9 |

## Port notes carried to Phase 6a

sql/silver_build.sql flags every point where DuckDB and Spark SQL diverge:
date_diff argument order, list_filter vs filter, UNNEST vs LATERAL VIEW
explode, and the Parquet glob becoming a Delta table reference. QUALIFY is
supported in both Spark 3.4+ and Fabric Warehouse.

## Carried into Phase 3 (Gold)

1. dim_zone with SCD2 change tracking (deferred from Phase 2)
2. dim_date, dim_vendor, dim_payment, dim_weather_band
3. fact_trip keyed on trip_id with surrogate dimension keys
4. Project the five Gold-facing booleans from dq_flags
5. Distance measures must use median; the mean is unusable

## Open questions

Unchanged from Phase 1: null-block trend past March, VendorID 6, and the 40x
zone concentration remain open.

## Assessment

The value of this phase was not the cleansing — it was that three separate
data-quality errors surfaced during the build and each was caught by a check
rather than shipped. A Silver layer that merely ran would have encoded all
three. The invariants are the deliverable; the clean table is a by-product.