-- ============================================================================
-- Gold build — NYC TLC yellow taxi, Kimball star schema
--
-- Dialect: DuckDB. Editor SQL linting (MSSQL) will flag DuckDB-specific
-- syntax (QUALIFY, list_contains, strftime, range()) as errors. These are
-- valid DuckDB and validated in notebooks/03_gold_build.ipynb.
--
-- Portable SQL extracted from notebooks/03_gold_build.ipynb.
-- Intended to port to Fabric Spark SQL / Warehouse in Phase 6a.
-- Divergence points are flagged inline as PORT NOTE.
--
-- Star:
--   fact_trip     one row per trip_id (grain = silver_trip)
--   dim_date      generated calendar, one row per day + unknown member (-1)
--   dim_zone      SCD2, as-of joined on pickup date
--   dim_vendor    static, includes unknown (-1) and undocumented code 6
--   dim_payment   static, TLC payment_type codes + unknown (-1)
--
-- Every dimension carries an unknown member at sk = -1 (ADR-005).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. dim_date — generated, not sourced. Full calendar year so time-intelligence
--    measures (YoY, MTD) have no gaps, even though trip data is Jan-Mar.
--    PORT NOTE: range(DATE, DATE, INTERVAL) is DuckDB. Spark SQL uses
--    sequence(start, stop, interval) then explode.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_date AS
WITH days AS (
    SELECT CAST(range AS DATE) AS date
    FROM range(DATE '2024-01-01', DATE '2025-01-01', INTERVAL 1 DAY)
)
SELECT
    CAST(strftime(date, '%Y%m%d') AS INTEGER) AS date_sk,
    date,
    EXTRACT(year    FROM date) AS year,
    EXTRACT(quarter FROM date) AS quarter,
    EXTRACT(month   FROM date) AS month,
    strftime(date, '%B')       AS month_name,
    EXTRACT(day     FROM date) AS day,
    EXTRACT(dayofweek FROM date) AS day_of_week,   -- 0 = Sunday
    strftime(date, '%A')       AS day_name,
    (EXTRACT(dayofweek FROM date) IN (0, 6)) AS is_weekend,
    FALSE AS is_us_holiday
FROM days;

-- major 2024 US federal holidays that shift NYC taxi demand (actual dates,
-- not observed dates — deliberate; demand shifts on the real day)
UPDATE dim_date SET is_us_holiday = TRUE
WHERE date IN (
    DATE '2024-01-01', DATE '2024-01-15', DATE '2024-02-19', DATE '2024-05-27',
    DATE '2024-06-19', DATE '2024-07-04', DATE '2024-09-02', DATE '2024-10-14',
    DATE '2024-11-11', DATE '2024-11-28', DATE '2024-12-25'
);

-- unknown member for out-of-period trips (2002, 2008, 2009, 2023) — ADR-005
INSERT INTO dim_date
SELECT -1, NULL, NULL, NULL, NULL, 'Unknown', NULL, NULL, 'Unknown', FALSE, FALSE;

-- ----------------------------------------------------------------------------
-- 2. dim_vendor — static. Includes unknown (-1) and the undocumented code 6
--    found in Phase 1 profiling.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_vendor AS
SELECT * FROM (VALUES
    (-1, 0, 'Unknown / not provided'),
    ( 1, 1, 'Creative Mobile Technologies'),
    ( 2, 2, 'Curb / VeriFone'),
    ( 3, 6, 'Undocumented vendor code 6')
) AS t(vendor_sk, vendor_id, vendor_name);

-- ----------------------------------------------------------------------------
-- 3. dim_payment — static, TLC data-dictionary codes + unknown (-1).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_payment AS
SELECT * FROM (VALUES
    (-1, 0, 'Unknown / not provided'),
    ( 1, 1, 'Credit card'),
    ( 2, 2, 'Cash'),
    ( 3, 3, 'No charge'),
    ( 4, 4, 'Dispute'),
    ( 5, 5, 'Unknown'),
    ( 6, 6, 'Voided trip')
) AS t(payment_sk, payment_type, payment_name);

-- ----------------------------------------------------------------------------
-- 4. dim_zone — SCD2. Initial load: every zone is_current, valid_to NULL.
--    row_hash covers only the SCD2-tracked attributes (borough, zone,
--    service_zone). location_id is the natural key and is NOT hashed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_zone AS
WITH src AS (
    SELECT
        CAST(LocationID AS INTEGER) AS location_id,
        Borough AS borough, Zone AS zone, service_zone
    FROM read_csv_auto('data/raw/taxi_zone_lookup.csv')
)
SELECT
    ROW_NUMBER() OVER (ORDER BY location_id) AS zone_sk,
    location_id, borough, zone, service_zone,
    md5(concat_ws('|', COALESCE(borough,''), COALESCE(zone,''),
        COALESCE(service_zone,''))) AS row_hash,
    DATE '2024-01-01' AS valid_from,
    CAST(NULL AS DATE) AS valid_to,
    TRUE AS is_current
FROM src;

INSERT INTO dim_zone
SELECT -1, -1, 'Unknown', 'Unknown', 'Unknown', md5('unknown'),
       DATE '2024-01-01', NULL, TRUE;

-- ----------------------------------------------------------------------------
-- 4b. SCD2 merge — the change-detection pattern.
--     A synthetic change (zone 1 service_zone) is injected to prove history
--     tracking (ADR-005). In Fabric this is a MERGE INTO against incoming data.
--     PORT NOTE: DuckDB uses UPDATE + INSERT in two steps. Fabric Delta uses
--     a single MERGE INTO ... WHEN MATCHED / WHEN NOT MATCHED.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE zone_incoming_hashed AS
SELECT location_id, borough, zone,
       CASE WHEN location_id = 1 THEN 'Airports (updated)' ELSE service_zone END AS service_zone,
       md5(concat_ws('|', COALESCE(borough,''), COALESCE(zone,''),
           COALESCE(CASE WHEN location_id = 1 THEN 'Airports (updated)'
                    ELSE service_zone END,''))) AS row_hash
FROM dim_zone WHERE is_current AND location_id <> -1;

-- close changed current rows
UPDATE dim_zone
SET valid_to = DATE '2024-06-01', is_current = FALSE
WHERE is_current AND location_id IN (
    SELECT i.location_id FROM zone_incoming_hashed i
    JOIN dim_zone d ON i.location_id = d.location_id AND d.is_current
    WHERE i.row_hash <> d.row_hash
);

-- insert new versions with fresh surrogate keys
INSERT INTO dim_zone
SELECT (SELECT MAX(zone_sk) FROM dim_zone)
         + ROW_NUMBER() OVER (ORDER BY i.location_id),
       i.location_id, i.borough, i.zone, i.service_zone, i.row_hash,
       DATE '2024-06-01', CAST(NULL AS DATE), TRUE
FROM zone_incoming_hashed i
JOIN dim_zone d ON i.location_id = d.location_id AND d.is_current = FALSE
WHERE d.valid_to = DATE '2024-06-01'
  AND NOT EXISTS (SELECT 1 FROM dim_zone c
                  WHERE c.location_id = i.location_id AND c.is_current);

-- ----------------------------------------------------------------------------
-- 5. fact_trip — grain = one row per trip_id. Dimensions joined by surrogate
--    key; unresolved FKs fall back to -1 (never NULL, never dropped).
--    dim_zone is joined AS-OF the pickup date, not the current version.
--    PORT NOTE: list_contains(array, x) is DuckDB; Spark SQL is
--    array_contains(array, x). QUALIFY / window syntax is unchanged.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE fact_trip AS
SELECT
    ROW_NUMBER() OVER (ORDER BY s.pickup_ts) AS trip_sk,
    s.trip_id,                                    -- degenerate dimension
    COALESCE(d.date_sk, -1)   AS date_sk,
    COALESCE(pz.zone_sk, -1)  AS pickup_zone_sk,
    COALESCE(dz.zone_sk, -1)  AS dropoff_zone_sk,
    COALESCE(v.vendor_sk, -1) AS vendor_sk,
    COALESCE(p.payment_sk,-1) AS payment_sk,
    s.passenger_count, s.trip_distance, s.trip_duration_min,
    s.fare_amount, s.total_amount, s.congestion_surcharge, s.airport_fee,
    s.is_billable,
    list_contains(s.dq_flags, 'NULL_BLOCK')     AS is_null_block,
    list_contains(s.dq_flags, 'ZERO_DISTANCE')  AS is_zero_distance,
    (list_contains(s.dq_flags, 'NEGATIVE_FARE')
     OR list_contains(s.dq_flags, 'NEGATIVE_TOTAL')) AS is_negative_amount,
    list_contains(s.dq_flags, 'UNKNOWN_VENDOR') AS is_unknown_vendor,
    len(s.dq_flags) AS dq_flag_count
FROM silver_trip s
LEFT JOIN dim_date d
    ON d.date_sk = CAST(strftime(s.partition_date, '%Y%m%d') AS INTEGER)
LEFT JOIN dim_zone pz
    ON pz.location_id = s.pu_location_id
   AND s.partition_date >= pz.valid_from
   AND (s.partition_date < pz.valid_to OR pz.valid_to IS NULL)
LEFT JOIN dim_zone dz
    ON dz.location_id = s.do_location_id
   AND s.partition_date >= dz.valid_from
   AND (s.partition_date < dz.valid_to OR dz.valid_to IS NULL)
LEFT JOIN dim_vendor v  ON v.vendor_id = s.vendor_id
LEFT JOIN dim_payment p ON p.payment_type = s.payment_type;