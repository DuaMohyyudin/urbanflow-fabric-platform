# Charter Traceability

Every charter commitment maps to a phase, an artefact, and evidence.
No row gets deleted. Scope changes get an ADR reference, not silence.

| # | Charter commitment | Phase | Artefact | Status | Evidence / ADR |
|---|---|---|---|---|---|
| 1 | Revenue per vehicle hour | 4 | DAX measure | Not started | |
| 2 | Idle time % | 4 | DAX measure | Not started | |
| 3 | Cancellation rate by zone | 6 | KQL + measure | Not started | |
| 4 | Forecast MAPE beats seasonal-naive | 7 | ai/forecast.ipynb | Not started | |
| 5 | Finance: P&L by zone and month, daily refresh | 5 | Exec P&L report | Not started | |
| 6 | Ops: where are vehicles idle right now | 6 | Real-time dashboard | Not started | |
| 7 | Exec: plain-English questions | 7 | NL query agent | Not started | |
| 8 | TLC trip records ingested | 1-3 | Bronze/Silver/Gold | In progress | |
| 9 | Zone lookup ingested | 1-3 | dim_zone (SCD2) | Not started | |
| 10 | Weather ingested | 1-3 | silver_weather_hourly | Not started | |
| 11 | Simulated event stream | 6 | streaming/producer.py | Not started | |
| 12 | End-to-end refresh under 15 min | 8 | Measured, documented | Not started | |
| 13 | All artefacts version-controlled | 0-9 | This repo | In progress | |
| 14 | Deployable via pipeline | 8 | Deployment pipeline | Not started | |
| 15 | Public data only, no client data | 0-9 | Ongoing discipline | Holding | |
| 16 | Total budget under $60 | 0-9 | Cost tracking | On track | |