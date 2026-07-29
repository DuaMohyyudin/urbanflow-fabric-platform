-- ============================================================================
-- Silver build — NYC TLC yellow taxi
--
-- Portable SQL extracted from notebooks/02_silver_build.ipynb.
-- Written against DuckDB. Intended to port to Fabric Spark SQL in Phase 6a
-- with minimal change. Divergence points are flagged inline as PORT NOTE.
--
-- Contract:
--   silver_trip            every physically possible row, with a dq_flags array
--   silver_trip_quarantine every impossible row, with the failing rule attached
--   dq_results             per-run, per-month, per-flag telemetry
--
-- Invariant: silver_trip + silver_trip_quarantine + collapsed_duplicates
--            = source row count.
-- ============================================================================

-- Replace the glob with the Lakehouse table/path in Fabric.
-- PORT NOTE: read_parquet glob becomes a Delta table reference in Phase 6a.

-- ----------------------------------------------------------------------------
-- 1. Typed base view. Derives trip_id, partition_date, duration, and keeps a
--    raw passenger column so flags read the source, not the cleaned value.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW bronze_typed AS
SELECT
    -- Deterministic business key. COALESCE guards against a NULL poisoning
    -- the whole hash. Includes signed total_amount and payment_type so a
    -- refund reversal is NOT mistaken for a duplicate of its charge.
    -- PORT NOTE: md5() and concat_ws() exist in Spark SQL; behaviour matches.
    md5(concat_ws('|',
        COALESCE(CAST(tpep_pickup_datetime  AS VARCHAR), ''),
        COALESCE(CAST(tpep_dropoff_datetime AS VARCHAR), ''),
        COALESCE(CAST(PULocationID AS VARCHAR), ''),
        COALESCE(CAST(DOLocationID AS VARCHAR), ''),
        COALESCE(CAST(trip_distance AS VARCHAR), ''),
        COALESCE(CAST(fare_amount   AS VARCHAR), ''),
        COALESCE(CAST(total_amount  AS VARCHAR), ''),
        COALESCE(CAST(payment_type  AS VARCHAR), ''),
        COALESCE(CAST(VendorID      AS VARCHAR), '')
    )) AS trip_id,

    CAST(VendorID AS INTEGER)                        AS vendor_id,
    tpep_pickup_datetime                             AS pickup_ts,
    tpep_dropoff_datetime                            AS dropoff_ts,
    CAST(tpep_pickup_datetime AS DATE)               AS partition_date,

    -- raw passenger value, used only for flag computation
    passenger_count                                  AS passenger_count_raw,

    -- 0 passengers means "not entered", not zero people
    CASE WHEN passenger_count = 0 THEN NULL
         ELSE CAST(passenger_count AS INTEGER) END   AS passenger_count,

    CAST(trip_distance AS DECIMAL(10,2))             AS trip_distance,
    CAST(RatecodeID AS INTEGER)                      AS ratecode_id,

    CASE WHEN store_and_fwd_flag = 'Y' THEN TRUE
         WHEN store_and_fwd_flag = 'N' THEN FALSE
         ELSE NULL END                               AS store_and_fwd,

    CAST(PULocationID AS INTEGER)                    AS pu_location_id,
    CAST(DOLocationID AS INTEGER)                    AS do_location_id,
    CAST(payment_type AS INTEGER)                    AS payment_type,

    CAST(fare_amount   AS DECIMAL(10,2))             AS fare_amount,
    CAST(total_amount  AS DECIMAL(10,2))             AS total_amount,
    CAST(congestion_surcharge AS DECIMAL(10,2))      AS congestion_surcharge,
    CAST(Airport_fee   AS DECIMAL(10,2))             AS airport_fee,

    -- PORT NOTE: DuckDB date_diff('minute', start, end).
    -- Spark SQL is (unix_timestamp(end) - unix_timestamp(start)) / 60.
    date_diff('minute', tpep_pickup_datetime, tpep_dropoff_datetime) AS trip_duration_min
FROM read_parquet('data/raw/yellow_tripdata_2024-*.parquet');

-- ----------------------------------------------------------------------------
-- 2. Flag view. Quarantine rules are the routing key; keep-flags are recorded.
--    All flags read passenger_count_raw, never the cleaned column.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW bronze_flagged AS
SELECT *,
    -- quarantine rules
    (dropoff_ts <= pickup_ts)          AS q_impossible_duration,
    (trip_duration_min > 720)          AS q_excessive_duration,
    (trip_distance > 200)              AS q_impossible_distance,

    -- keep-and-flag rules
    (passenger_count_raw IS NULL)      AS f_null_block,
    (passenger_count_raw = 0)          AS f_zero_passengers,
    (fare_amount < 0)                  AS f_negative_fare,
    (total_amount < 0)                 AS f_negative_total,
    (trip_distance = 0)                AS f_zero_distance,
    (vendor_id NOT IN (1, 2))          AS f_unknown_vendor,
    (partition_date <  DATE '2024-01-01'
        OR partition_date >= DATE '2024-04-01') AS f_out_of_period
FROM bronze_typed;

-- ----------------------------------------------------------------------------
-- 3. Quarantine table — physically impossible rows, failing rule attached.
--    PORT NOTE: list_filter(list, lambda) becomes filter(array, lambda) in
--    Spark SQL; both drop NULLs from the constructed array.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE silver_trip_quarantine AS
SELECT
    trip_id, vendor_id, pickup_ts, dropoff_ts, partition_date,
    trip_distance, trip_duration_min, fare_amount, total_amount,
    pu_location_id, do_location_id,
    list_filter([
        CASE WHEN q_impossible_duration THEN 'IMPOSSIBLE_DURATION' END,
        CASE WHEN q_excessive_duration  THEN 'EXCESSIVE_DURATION'  END,
        CASE WHEN q_impossible_distance THEN 'IMPOSSIBLE_DISTANCE' END
    ], x -> x IS NOT NULL) AS quarantine_flags
FROM bronze_flagged
WHERE q_impossible_duration OR q_excessive_duration OR q_impossible_distance;

-- ----------------------------------------------------------------------------
-- 4. Clean table — everything possible, keep-flags recorded, exact duplicates
--    collapsed to one row per trip_id (ADR-004). Refund pairs survive because
--    signed total_amount is part of the hash.
--    PORT NOTE: QUALIFY is supported in Spark SQL 3.4+ and in Fabric Warehouse.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE silver_trip AS
SELECT
    trip_id, vendor_id, pickup_ts, dropoff_ts, partition_date,
    passenger_count, trip_distance, ratecode_id, store_and_fwd,
    pu_location_id, do_location_id, payment_type,
    fare_amount, total_amount, congestion_surcharge, airport_fee,
    trip_duration_min,
    (total_amount > 0 AND trip_distance > 0) AS is_billable,
    list_filter([
        CASE WHEN f_null_block      THEN 'NULL_BLOCK'      END,
        CASE WHEN f_negative_fare   THEN 'NEGATIVE_FARE'   END,
        CASE WHEN f_negative_total  THEN 'NEGATIVE_TOTAL'  END,
        CASE WHEN f_zero_distance   THEN 'ZERO_DISTANCE'   END,
        CASE WHEN f_zero_passengers THEN 'ZERO_PASSENGERS' END,
        CASE WHEN f_unknown_vendor  THEN 'UNKNOWN_VENDOR'  END,
        CASE WHEN f_out_of_period   THEN 'OUT_OF_PERIOD'   END
    ], x -> x IS NOT NULL) AS dq_flags
FROM bronze_flagged
WHERE NOT (q_impossible_duration OR q_excessive_duration OR q_impossible_distance)
QUALIFY ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY pickup_ts) = 1;

-- ----------------------------------------------------------------------------
-- 5. Run telemetry — per-run, per-month, per-flag counts. Appends over time in
--    Fabric; recreated here for the local single-run case.
--    PORT NOTE: UNNEST(array) AS t(col) becomes LATERAL VIEW explode(array)
--    in Spark SQL.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE dq_results AS
SELECT
    current_date                     AS run_date,
    date_trunc('month', pickup_ts)   AS partition_month,
    flag,
    COUNT(*)                         AS row_count
FROM silver_trip, UNNEST(dq_flags) AS t(flag)
GROUP BY 1, 2, 3
ORDER BY 2, 3;