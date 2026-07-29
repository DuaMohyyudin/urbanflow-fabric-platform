# Gold Layer Specification

## Purpose
Gold is the consumption layer: a Kimball star schema the semantic model
reads directly. One fact, four dimensions, conformed keys, surrogate keys
everywhere.

## Grain
fact_trip: one row per trip_id (the Silver business key).

## Star

fact_trip
  - trip_sk           surrogate, identity
  - trip_id           degenerate dimension (the Silver hash, for traceability)
  - date_sk           FK to dim_date       (from pickup date)
  - pickup_zone_sk    FK to dim_zone       (SCD2 current or as-of)
  - dropoff_zone_sk   FK to dim_zone
  - vendor_sk         FK to dim_vendor
  - payment_sk        FK to dim_payment
  - passenger_count, trip_distance, trip_duration_min
  - fare_amount, total_amount, congestion_surcharge, airport_fee
  - is_billable
  - is_null_block, is_zero_distance, is_negative_amount,
    is_unknown_vendor        (projected from dq_flags)
  - dq_flag_count

dim_date        one row per calendar day, generated in SQL
dim_zone        SCD2: zone_sk, location_id, borough, zone, service_zone,
                row_hash, valid_from, valid_to, is_current
dim_vendor      small static dim (1, 2, and 6-unknown)
dim_payment     small static dim (TLC payment_type codes)

## Surrogate keys
Every dimension has an integer surrogate key independent of the source
business key. Facts join on surrogate keys, never on natural keys.
An "unknown" member (sk = -1) exists in every dimension for orphan/NULL FKs.

## SCD2 on dim_zone
- row_hash = md5 of (borough, zone, service_zone)
- On load, compare incoming row_hash to the current record's hash
- If changed: close the old row (valid_to = today, is_current = false)
  and insert a new row (valid_from = today, is_current = true)
- If unchanged: no-op
- A synthetic change will be injected once to prove history is tracked.

Note: the TLC zone lookup is effectively static. SCD2 here is a
demonstrated capability, not an operational necessity — recorded honestly
in the phase log.

## dim_date
Generated, not sourced. Columns: date_sk (yyyymmdd int), date,
year, quarter, month, month_name, day, day_of_week, day_name,
is_weekend, is_us_holiday (major federal holidays for demand analysis).

## The five booleans on the fact
Projected from the Silver dq_flags array so measures do not have to parse
an array in DAX:
- is_null_block          = 'NULL_BLOCK' in dq_flags
- is_zero_distance       = 'ZERO_DISTANCE' in dq_flags
- is_negative_amount     = 'NEGATIVE_FARE' or 'NEGATIVE_TOTAL' in dq_flags
- is_unknown_vendor      = 'UNKNOWN_VENDOR' in dq_flags
- dq_flag_count          = array length
The rest stay in Silver.

## Invariants for Gold
1. Every fact FK resolves to a dimension row (no orphans, unknown member ok)
2. fact_trip row count = silver_trip row count (grain preserved)
3. dim_zone has exactly one is_current = true row per location_id
4. No surrogate key is NULL
5. Sum of a money measure over the fact = same sum over silver_trip
   (nothing lost or double-counted in the join)