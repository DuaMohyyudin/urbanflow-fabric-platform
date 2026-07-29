# Phase 3 Log — Gold Star Schema

**Date:** 2026-07-29 · **Planned:** Week 4 · **Cost incurred:** $0

## Objective
Build a Kimball star schema over Silver: one fact, four dimensions, surrogate
keys throughout, SCD2 on dim_zone, every rule enforced by an invariant.

## Delivered

| # | Item | Evidence |
|---|---|---|
| 1 | Gold build notebook | notebooks/03_gold_build.ipynb |
| 2 | Portable SQL for the Fabric port | sql/gold_build.sql |
| 3 | dim_date, generated, full year + unknown member | 367 rows |
| 4 | dim_vendor, dim_payment (static, with unknown members) | 4 / 7 rows |
| 5 | dim_zone with SCD2 and a proven change | 267 rows |
| 6 | fact_trip, grain preserved | 9,546,890 rows |
| 7 | Eight Gold invariants, all passing | notebook cell 10 |
| 8 | ADR-005 unknown members and as-of SCD2 | docs/adr/adr-005-unknown-members.md |

## The star

```
              dim_date
                 |
   dim_zone --- fact_trip --- dim_vendor
   (SCD2)         |
             dim_payment
```

Grain: one row per trip_id. Facts join dimensions by surrogate key only.
Every dimension has an unknown member at sk = -1.

## SCD2, demonstrated not just designed

dim_zone tracks borough, zone and service_zone via a row_hash. A synthetic
change was injected — zone 1 (Newark Airport) service_zone EWR ->
'Airports (updated)', effective 2024-06-01 — and the merge produced two
versions:

| zone_sk | zone | service_zone | valid_from | valid_to | is_current |
|---|---|---|---|---|---|
| 1 | Newark Airport | EWR | 2024-01-01 | 2024-06-01 | false |
| 266 | Newark Airport | Airports (updated) | 2024-06-01 | (null) | true |

The row_hash compared 265 incoming zones and flagged exactly one as changed
— no false positives. This is the surrogate-key + rowhash change-detection
pattern applied to a real dimension.

fact_trip joins dim_zone as-of the pickup date. Because trip data is Jan-Mar
and the change lands in June, all current trips resolve to the pre-change
version — which is exactly what an as-of join should do.

## One problem found and fixed

fact_trip first returned 9,546,872 rows — 18 short of Silver. An inner join
to dim_date silently dropped trips dated 2002, 2008, 2009 and 2023 (the
out-of-period rows from Phase 1). Fixed by adding an unknown date member
(sk = -1) and a left join, routing those 18 rows to -1 instead of dropping
them. Grain restored to 9,546,890. Caught by invariant G1, not by luck.

## Eight invariants (all passing)

| # | Invariant | Result |
|---|---|---|
| G1 | fact rows = silver rows (grain preserved) | PASS |
| G2 | no NULL surrogate keys | PASS |
| G3 | every fact FK resolves (date, zone, vendor, payment) | PASS |
| G4 | exactly one is_current row per location_id | PASS |
| G5 | fact money total = silver money total | PASS (0.00) |

G5 is the strongest check: after four joins including two SCD2 as-of joins,
the sum of total_amount matches Silver to the penny, proving no join
duplicated or dropped a row.

## Design decisions

| Decision | Rationale | Reference |
|---|---|---|
| Unknown member (-1) in every dimension | FKs never NULL, rows never dropped | ADR-005 |
| as-of SCD2 join, not current | The real SCD2 pattern; interview-relevant | ADR-005 |
| Retain the synthetic zone change | Keeps the SCD2 proof visible in the repo | ADR-005 |
| Full-year dim_date | Time-intelligence measures need a gapless calendar | Kimball |
| Actual holiday dates, not observed | Taxi demand shifts on the real day | phase log |
| Five booleans projected from dq_flags | DAX should not parse an array | gold-spec |

## Port notes carried to Phase 6a

sql/gold_build.sql flags every DuckDB/Spark divergence: range() vs sequence(),
list_contains vs array_contains, and the two-step UPDATE+INSERT SCD2 becoming
a single MERGE INTO on Delta.

## Carried into Phase 4 (semantic model + DAX)

1. Distance measures use median, not mean (Phase 1 finding)
2. Exclude is_zero_distance rows from revenue-per-mile
3. RLS by borough for the region-manager persona
4. Time-intelligence measures on dim_date (YoY, MTD, rolling 28d)
5. Calculation group for the time-intelligence set

## Assessment
The star schema is unremarkable to build and easy to build wrong. The value
was G5 and G1: two invariants that would have caught a duplicating join or a
silent row drop, and G1 did catch one. The dimensional model is the
deliverable everyone expects; the proof that it conserves rows and money is
the part that is usually missing.