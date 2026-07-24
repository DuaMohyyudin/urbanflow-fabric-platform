# UrbanFlow — Project Charter

## Problem
A city ride-hail/fleet operator loses margin on three things:
idle vehicles parked in low-demand zones, pricing decisions made on
stale data, and no early warning when cancellations spike in a zone.

## Stakeholders and what they need
| Stakeholder | Question they ask | Cadence |
|---|---|---|
| Finance | What is P&L by zone and by month? | Daily refresh |
| Operations | Where are vehicles idle right now? | Live |
| Executive | Why did revenue move? Answer in plain English | On demand |

## KPIs
- Revenue per vehicle hour
- Idle time %
- Cancellation rate by zone
- Forecast accuracy (MAPE) for next-hour demand per zone

## Scope
In scope: batch ingestion of historic trips, weather and zone data;
streaming trip and telemetry events; dimensional model; four Power BI
reports; demand forecasting; a natural-language ops assistant.

Out of scope: real pricing engine, driver mobile app, payment processing.

## Data sources
| Source | Type | Grain |
|---|---|---|
| NYC TLC trip records | Batch, Parquet | One row per trip |
| TLC taxi zone lookup | Batch, CSV | One row per zone |
| Open-Meteo | Batch, API | Hourly weather |
| Simulated event stream | Streaming | Trip and vehicle events |

## Constraints
- Fabric trial capacity: 60 days, activate at Phase 6
- Budget target: under $60 total
- Public data only. No client or employer data at any point.

## Success criteria
- End-to-end refresh completes under 15 minutes
- Every report question above answerable from the semantic model
- All artefacts version-controlled and deployable via pipeline
- Forecast beats a seasonal-naive baseline

## Non-goals
This is a self-directed portfolio build, not a production system
and not client work.