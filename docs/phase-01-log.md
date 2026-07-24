# Phase 1 Log — Bronze Ingestion and Profiling

**Date:** 2026-07-24 · **Planned:** Week 2 · **Actual:** same day as Phase 0
**Cost incurred:** $0

## Objective

Understand the data before building for it. No transformation logic, no
schema design, no cloud resources — only ingestion and measurement.

## Delivered

| # | Item | Evidence |
|---|---|---|
| 1 | Reproducible Python environment | `.venv`, `requirements.txt` |
| 2 | Idempotent ingestion script | `scripts/download_tlc.py` |
| 3 | Raw data landed: 3 months + zone lookup | `data/raw`, ~160 MB, gitignored |
| 4 | Profiling notebook, 17 checks | `notebooks/01_profile_bronze.ipynb` |
| 5 | Quality verdicts for 12 findings | `docs/data-quality.md` |
| 6 | Lessons log | `docs/lessons.md` |

## Headline numbers

| Metric | Value |
|---|---:|
| Rows profiled | 9,554,778 |
| Distinct issues catalogued | 12 |
| Rows in the optional-field null block | 751,962 (7.87%) |
| Null-block rate, January → March | 4.73% → 11.90% |
| Rows quarantined outright (Q6+Q7+Q8) | 7,878 (0.08%) |
| Rows flagged but retained | ~1.1M |
| Orphan zone IDs | 0 |
| Probable duplicates | 1 |
| Rows that distorted mean trip distance 4.1x | 122 |

## Method note

DuckDB queried the Parquet files in place — no server, no connection string,
no credentials, no data movement. The engine runs inside the Python process.

This is deliberate: the SQL written here transfers directly to the Fabric
Warehouse in Phase 3, but the profiling cost nothing and did not consume any
of the 60-day trial capacity. Phase 6 is when that clock should start.

## Decisions taken

| Decision | Rationale |
|---|---|
| Flag rather than delete | 1.4% of rows have negative fares. They are refunds, and Finance needs them. |
| Quarantine rather than drop | 7,878 impossible rows are retained with their failing rule attached, so the exclusion is auditable. |
| Partition by pickup date | The March file contains April and 2002 rows. Filenames do not describe contents. |
| Median over mean for distance | The mean is unusable on this column. |
| Start with 3 months, not 18 | Schema and quality rules first; volume after. |

## What changed my mind

Three hypotheses about the null block were rejected in sequence —
vendor-specific, airport-related, and genuinely-longer-trips. Each was
plausible, each was supported by the summary statistic in front of me, and
each was wrong. The correcting evidence was, in order: a per-vendor
breakdown, a dropoff-zone geography check, and a percentile distribution.

The value of Phase 1 was not the twelve findings. It was discovering that
the obvious reading of the data was inverted, before any of it was encoded
into a transformation.

## Carried into Phase 2

1. `dq_flag` on every row — nothing silently dropped
2. `silver_trip_quarantine` for Q6, Q7, Q8
3. Partition by pickup date, never filename
4. `dq_results` table emitting the per-month null-block rate on every run
5. Distance measures use median; Q4 and Q8 excluded in DAX, not in the fact
6. Bronze must tolerate additive schema drift (`cbd_congestion_fee`, 2025+)

## Open questions

- Does the null-block rate keep climbing past March 2024?
- Is `VendorID` 6 a new entrant or a coding error?
- Why does the null-block rate vary 40x across pickup zones?

## Assessment

Phases 0 and 1 both completed on day one against a two-week plan. The
schedule gain is real but should not be spent — Phase 4 (semantic model and
DAX) and Phase 7 (AI evaluation) are the phases where rushing produces work
that does not survive scrutiny. Treat the gain as buffer, not as progress.
