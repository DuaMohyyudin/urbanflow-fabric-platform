# Data Quality — Bronze Profile and Silver Verdicts

**Source:** NYC TLC yellow taxi trip records, 2024-01 to 2024-03
**Rows profiled:** 9,554,778
**Method:** DuckDB queried the raw Parquet files in place — no server, no
credentials, no data movement, no cost.
**Notebooks:** `notebooks/01_profile_bronze.ipynb` (profiling),
`notebooks/02_silver_build.ipynb` (Silver build and invariants)
**First written:** 2026-07-24 · **Updated:** 2026-07-29 (Phase 2)

---

## 1. Schema

19 columns. All nullable. Types as delivered by the source:

| Column | Type | Column | Type |
|---|---|---|---|
| VendorID | INTEGER | payment_type | BIGINT |
| tpep_pickup_datetime | TIMESTAMP | fare_amount | DOUBLE |
| tpep_dropoff_datetime | TIMESTAMP | extra | DOUBLE |
| passenger_count | BIGINT | mta_tax | DOUBLE |
| trip_distance | DOUBLE | tip_amount | DOUBLE |
| RatecodeID | BIGINT | tolls_amount | DOUBLE |
| store_and_fwd_flag | VARCHAR | improvement_surcharge | DOUBLE |
| PULocationID | INTEGER | total_amount | DOUBLE |
| DOLocationID | INTEGER | congestion_surcharge | DOUBLE |
| | | Airport_fee | DOUBLE |

Note: TLC added a `cbd_congestion_fee` column to Yellow, Green and HVFHV
datasets from 2025 onward. Any extension of the window past 2024 will hit
schema drift. The Bronze layer must tolerate additive schema change.

## 2. Volume and range

| Metric | Value |
|---|---|
| Rows | 9,554,778 |
| Min pickup | 2002-12-31 22:17:10 |
| Max pickup | 2024-04-01 00:34:55 |

The declared window is January–March 2024. The observed range is 22 years.

## 3. Findings and verdicts

| # | Finding | Count | % of rows | Verdict | Rationale |
|---|---|---:|---:|---|---|
| Q1 | Five optional fields null together | 751,962 | 7.87% | **Keep + flag** | Ordinary trips with unreported optional fields. See section 4. |
| Q2 | fare_amount < 0 | 136,567 | 1.43% | **Keep + flag** | Refunds and disputes are real transactions. Finance needs them. |
| Q3 | total_amount < 0 | 115,895 | 1.21% | **Keep + flag** | Same as Q2. |
| Q4 | trip_distance = 0 | 215,764 | 2.26% | **Flag, exclude from distance KPIs** | Meter fault or cancellation. Destroys revenue-per-mile. |
| Q5 | passenger_count = 0 | 105,931 | 1.11% | **Keep, map to unknown** | Driver did not enter a value. Not a data error. |
| Q6 | dropoff <= pickup | 2,801 | 0.03% | **Quarantine** | Physically impossible. Duration is uncomputable. |
| Q7 | Duration > 12 hours | 4,916 | 0.05% | **Quarantine** | Meter left running. |
| Q8 | trip_distance > 200 mi | 170 | 0.00% | **Quarantine** | Not plausible for a yellow cab. Max observed: 312,722 mi. |
| Q9 | Pickup outside declared period | 21 | 0.00% | **Route by pickup date** | Includes 2002-12, 2008-12, 2009-01, 2023-12, 2024-04. |
| Q10 | VendorID = 6 | 720 | 0.01% | **Keep + flag** | Not in the TLC data dictionary, which defines 1 and 2 only. |
| Q11 | Orphan PULocationID | 0 | 0.00% | **No action** | Referential integrity is clean. |
| Q12 | Duplicates | see section 5 | — | **Collapse exact, keep refund pairs** | See correction below. |

> Q7 count is 4,916 as measured in Phase 2 after the passenger_count = 0 to
> NULL mapping shifted a boundary; Phase 1 reported 4,907. The 9-row
> difference is immaterial and noted for traceability.

### Q9 detail — rows by pickup month

| Month | Rows |
|---|---:|
| 2002-12 | 4 |
| 2008-12 | 1 |
| 2009-01 | 4 |
| 2023-12 | 10 |
| 2024-01 | 2,964,617 |
| 2024-02 | 3,007,533 |
| 2024-03 | 3,582,607 |
| 2024-04 | 2 |

The March file contains April rows — a legitimate post-midnight trip.
The filename does not describe the contents.

---

## 4. Q1 in detail — three rejected hypotheses

Columns null together: passenger_count, RatecodeID, store_and_fwd_flag,
congestion_surcharge, Airport_fee. Counts are identical to the row, so this
is a single submission path, not random missingness.

### H1 — vendor-specific. Rejected.

| VendorID | Rows | Null block | % |
|---:|---:|---:|---:|
| 2 | 7,219,832 | 542,016 | 7.51% |
| 1 | 2,334,226 | 209,226 | 8.96% |
| 6 | 720 | 720 | 100.00% |

Both major vendors are affected at comparable rates. VendorID 6 is fully
affected but is only 720 rows.

### H2 — long airport trips. Rejected.

Mean distance of 11.69 mi versus 3.39 mi suggested airport runs. Pickup and
dropoff zones are Manhattan-to-Manhattan. Several dropoff zones showed a
24 mi average inside an island 13 mi long — which falsifies the geography,
not just the hypothesis.

### H3 — genuinely longer trips. Rejected on percentiles.

| Group | Rows | p50 | p90 | p99 | Max | Mean |
|---|---:|---:|---:|---:|---:|---:|
| null_block | 751,962 | 2.08 | 6.23 | 16.19 | 312,722.3 | 11.69 |
| normal | 8,802,816 | 1.69 | 8.60 | 20.01 | 98,229.4 | 3.39 |

Null-block trips are **shorter** than normal at p90 and p99.

### Root cause

| Group | Rows | trip_distance > 100 mi | % |
|---|---:|---:|---:|
| null_block | 751,962 | 122 | 0.0162% |
| normal | 8,802,816 | 130 | 0.0015% |

Capping distance at 100 mi moves the null-block mean from **11.69 to 2.85**.

**122 rows — 0.0013% of the dataset — inflated the mean 4.1x and reversed
the direction of the finding.** Null-block trips are shorter than normal
(2.85 vs 3.39), not 3.4x longer. Three hypotheses were built on that mean
before the distribution was checked.

Corrupt distance values are concentrated 11x more heavily in the null block,
so the two facts coexist: these are ordinary, slightly shorter trips, from a
submission path that also produces more corrupt distances.

### Onset — a ramp, not a step

| Month | Rows | Null block | % |
|---|---:|---:|---:|
| 2024-01 | 2,964,617 | 140,162 | 4.73% |
| 2024-02 | 3,007,533 | 185,610 | 6.17% |
| 2024-03 | 3,582,607 | 426,190 | 11.90% |

Daily rate rises steadily with weekly seasonality — roughly 3–5% in early
January to 15–20% by late March. No single-day discontinuity, so this is a
phased rollout rather than a switchover. Linear extrapolation puts a
12-month window above 25%.

**This must be monitored per month, not checked once.** It is now emitted to
dq_results on every Silver run (see section 6).

### Geographic concentration

Zones with more than 10,000 trips, ranked by null-block rate:

| Zone | Trips | Null block | % |
|---|---:|---:|---:|
| Alphabet City | 15,879 | 6,340 | 39.93% |
| Central Harlem North | 12,059 | 4,197 | 34.80% |
| Two Bridges/Seward Park | 14,069 | 4,887 | 34.74% |
| Stuy Town/Peter Cooper Village | 14,005 | 4,684 | 33.45% |
| East Harlem North | 23,130 | 6,041 | 26.12% |
| Central Harlem | 24,997 | 6,383 | 25.54% |
| Chinatown | 13,939 | 2,778 | 19.93% |
| Seaport | 16,760 | 3,150 | 18.79% |

Rates vary 40x across zones, so the submission path is not evenly
distributed. Ranking by raw count returns the busiest Manhattan zones and
tells you nothing — see docs/lessons.md.

---

## 5. Q12 — duplicates, corrected in Phase 2

The Phase 1 duplicate check used 6 columns and reported **1 probable
duplicate**. The Phase 2 trip_id hash uses 9 business columns, including
signed total_amount and payment_type, and revealed the fuller picture:

- **333 refund pairs.** A +N charge and its -N reversal at an identical
  timestamp, same pickup, same dropoff, same everything except the sign of
  total_amount. These are **distinct financial transactions, not
  duplicates.** They were being collapsed only because the first hash
  excluded total_amount. Adding it separates them. They are **retained**.
- **1 genuine duplicate.** Two byte-identical rows — same trip recorded twice
  at source. This carries no information and is **collapsed** to one row
  (ADR-004).

The lesson: a business key must include the columns that make two rows
genuinely different. For financial data, the signed amount is one of them.
See docs/lessons.md.

---

## 6. Rules for the Silver layer

All of these are implemented in notebooks/02_silver_build.ipynb and enforced
by seven invariants that pass on every run.

1. **Every row carries a dq_flags array.** Nothing is silently dropped. A row
   is flagged, quarantined, or clean — and the reason is recorded.
2. **Quarantine, do not delete.** Q6, Q7 and Q8 go to
   silver_trip_quarantine with the failing rule attached.
3. **Collapse exact duplicates only.** Byte-identical rows are reduced to one
   (ADR-004); refund pairs are preserved.
4. **Partition by pickup date, never by filename.** March files contain April
   rows and rows dated 2002.
5. **passenger_count = 0 maps to unknown** (NULL), flagged ZERO_PASSENGERS.
6. **Flags read the raw source, not the cleaned column.** Computing
   NULL_BLOCK after the 0 to NULL mapping inflated it by ~105k rows until a
   raw passenger column was preserved for flagging.
7. **Distance measures use median or a trimmed mean.** Any measure built on
   AVERAGE(trip_distance) is wrong by ~4x on the affected segment. Q4 and Q8
   rows are excluded in DAX, not filtered out of the fact table.
8. **Emit the per-month flag counts to dq_results on every run**, so the Q1
   trend and every other rule stay visible over time.
9. **Money is stored as DECIMAL(10,2)**, not DOUBLE — floating-point sums
   drift, and Finance will notice.
10. **Tolerate additive schema change.** cbd_congestion_fee appears from 2025
    onward.

## 7. Silver invariants (all passing)

| # | Invariant | Result |
|---|---|---|
| 1 | silver + quarantine + collapsed duplicates = source | PASS |
| 2 | No trip_id appears in both tables | PASS |
| 3 | Every quarantined row has at least one quarantine flag | PASS |
| 4 | dq_flags is never NULL | PASS |
| 5 | No clean row breaks a quarantine rule | PASS |
| 6 | partition_date always derives from pickup | PASS |
| 7 | trip_id is unique in silver_trip | PASS |

Row disposition: 9,546,890 clean, 7,887 quarantined, 1 duplicate collapsed,
9,554,778 source. Conserved.

## 8. Open questions

- Does the null-block rate keep climbing past March 2024?
- Is VendorID 6 a new entrant, a test harness, or a coding error?
- Why is the null block concentrated in specific zones at 40x the rate of
  others?
- Are the 122 corrupt-distance rows recoverable from pickup/dropoff zone
  pairs, or should they be quarantined outright in a later pass?