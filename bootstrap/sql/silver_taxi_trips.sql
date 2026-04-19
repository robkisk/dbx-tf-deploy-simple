-- Silver table for SDP pipeline.
-- Pipeline-level catalog + schema are set on the databricks_pipeline resource
-- (catalog = bu1_dev, schema = mcp_demo), so unqualified names here resolve
-- against those defaults.

CREATE OR REFRESH STREAMING TABLE silver_taxi_trips
CLUSTER BY (pickup_borough)
COMMENT 'Cleaned + enriched taxi trips — borough joined from zip_borough_lookup, duration computed'
AS
SELECT
  t.tpep_pickup_datetime,
  t.tpep_dropoff_datetime,
  t.trip_distance,
  t.fare_amount,
  t.pickup_zip,
  t.dropoff_zip,
  pzb.borough AS pickup_borough,
  dzb.borough AS dropoff_borough,
  TIMESTAMPDIFF(MINUTE, t.tpep_pickup_datetime, t.tpep_dropoff_datetime) AS trip_duration_minutes
FROM stream(bu1_dev.mcp_demo.nyc_taxi_trips) t
LEFT JOIN bu1_dev.mcp_demo.zip_borough_lookup pzb ON t.pickup_zip = pzb.zip
LEFT JOIN bu1_dev.mcp_demo.zip_borough_lookup dzb ON t.dropoff_zip = dzb.zip
WHERE t.fare_amount > 0
  AND t.trip_distance > 0
  AND pzb.borough IS NOT NULL;
