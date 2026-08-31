CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS marts;
CREATE SCHEMA IF NOT EXISTS quality;

SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('raw', 'staging', 'marts', 'quality')
ORDER BY schema_name;
