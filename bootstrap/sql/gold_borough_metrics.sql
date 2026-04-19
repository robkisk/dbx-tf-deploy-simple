CREATE OR REFRESH MATERIALIZED VIEW gold_borough_metrics
COMMENT 'Aggregated taxi metrics per pickup borough'
AS
SELECT
  pickup_borough,
  COUNT(*)                                AS total_trips,
  ROUND(AVG(fare_amount), 2)              AS avg_fare,
  ROUND(AVG(trip_distance), 2)            AS avg_distance_miles,
  ROUND(AVG(trip_duration_minutes), 2)    AS avg_duration_min,
  ROUND(SUM(fare_amount), 2)              AS total_revenue
FROM silver_taxi_trips
GROUP BY pickup_borough;
