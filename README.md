# Personal Finance Analytics Warehouse + BI Dashboard

This project turns a personal finance tracker into a small analytics warehouse and BI dashboard.

## Planned Pipeline

1. Export transactions from Google Sheets as CSV.
2. Load the raw CSV into PostgreSQL.
3. Clean and standardize the data with Python and SQL.
4. Build reporting views for Power BI.
5. Add data quality checks.
6. Publish an anonymized sample dataset and dashboard screenshots.

## Tech Stack

- Python for ingestion, cleaning, validation, and anonymized sample data generation
- PostgreSQL for the analytics warehouse
- SQL for staging, dimensions, facts, and dashboard-ready marts
- Power BI for reporting and business analysis

## Data Privacy

Real transaction exports belong in `data/raw/` and are ignored by Git.
Only anonymized or fake sample data should be committed.
