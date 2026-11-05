# Personal Finance Analytics Warehouse + BI Dashboard

A portfolio data analytics project that turns personal-finance transactions from Google Sheets into a PostgreSQL analytics warehouse and Power BI reporting model.

The project demonstrates an end-to-end BI workflow: data ingestion, cleaning, reference-driven transformation, dimensional modeling, data-quality monitoring, and dashboard development.

> **Status:** Active development. The V2 data model supports expenses, income, refunds, people, payment methods, accounts, categories, and subcategories.

## Dashboard Visuals

<!--
Add public screenshots here when they are ready. Store them in:
dashboard/assets/screenshots/

Suggested filenames:
- 01-executive-summary.png
- 02-spending-analysis.png
- 03-star-schema.png
- 04-data-quality-checks.png

Use descriptive alt text with each image. Do not include private personal data.
-->

## Business Problem

Personal-finance data is often stored in spreadsheets that are useful for entry but difficult to analyze consistently over time. This project creates a repeatable analytics pipeline that preserves raw data, standardizes transactions, validates business rules, and produces a reporting-ready model for Power BI.

## Architecture

```text
Google Sheets / CSV Export
          |
          v
Python Ingestion Script
          |
          v
raw.transactions
          |
          v
staging.transactions
          |
          v
PostgreSQL Star Schema
          |
          v
Power BI Dashboard
```

## Data Model

The warehouse uses a small star schema centered on `marts.fct_transactions`.

| Table | Purpose |
| --- | --- |
| `marts.fct_transactions` | One row per financial transaction |
| `marts.dim_date` | Calendar attributes for time-based analysis |
| `marts.dim_category` | Category, subcategory, expense group, and fixed/variable classification |
| `marts.dim_source` | Standardized merchant, employer, or transaction source |
| `marts.dim_person` | Person associated with the transaction |
| `marts.dim_account` | Payment method and account combinations |

This design keeps transaction-level detail in the fact table while allowing Power BI to filter and aggregate consistently through dimensions.

## Key Capabilities

- Imports V2 transaction CSV files into PostgreSQL with Python and pandas.
- Normalizes CSV column names and validates required fields before loading.
- Adds ingestion metadata: source file, load timestamp, and original row number.
- Preserves the raw layer separately from transformed analytics tables.
- Standardizes known source-name variations while retaining raw source values.
- Supports `Expense`, `Income`, and `Refund` transaction types.
- Calculates signed amounts consistently: expenses are negative; income and refunds are positive.
- Uses reference tables to control valid categories, subcategories, people, payment methods, and accounts.
- Provides dashboard-ready SQL views for monthly cash flow, savings rate, category spending, top sources, rolling spend, recurring-expense candidates, and month-over-month changes.
- Includes data-quality checks for missing values, invalid reference values, refund relationships, future dates, duplicate candidates, and account combinations.

## Data Quality

The `quality` schema identifies issues before they reach reporting.

Examples of validation rules include:

- Missing or invalid transaction dates
- Missing, negative, or zero amounts
- Invalid transaction types
- Invalid category and subcategory combinations
- Invalid people, payment methods, or account combinations
- Refunds without a valid original expense transaction
- Refund totals greater than their original expense
- Future-dated transactions
- Suspicious duplicate source/date/amount combinations
- Transactions still classified as `Other / To Review`

## Technology Stack

- **Python:** CSV ingestion and validation
- **pandas:** File loading and lightweight data inspection
- **PostgreSQL:** Data warehouse, transformations, views, and quality checks
- **SQLAlchemy + psycopg:** Database connectivity
- **Power BI:** Data model, DAX measures, and interactive reporting
- **Google Sheets:** Transaction-entry source system

## Repository Structure

```text
data/
  raw/          # Private source exports; excluded from Git
  sample/       # Safe synthetic data for development and demonstration

scripts/
  load_raw_transactions.py
  check_db_connection.py

sql/
  schema/       # PostgreSQL schemas
  reference/    # Controlled values and mappings
  staging/      # Cleaned transaction layer
  marts/        # Star schema and reporting views
  quality/      # Data-quality audit views

dashboard/
  assets/       # Public screenshots, themes, and dashboard assets
```

## Running the Project

1. Create a PostgreSQL database and configure connection details in `.env` using `.env.example` as a template.
2. Install dependencies:

   ```bash
   pip install -r requirements.txt
   ```

3. Run the schema and reference-data SQL scripts.
4. Load the synthetic demo CSV:

   ```powershell
   python scripts/load_raw_transactions.py `
     --input data/sample/transactions_demo_2024-10-01_to_2026-09-30.csv
   ```

5. Run the staging, marts, dashboard-view, and quality-check SQL scripts in order.
6. Connect Power BI to the `marts` schema and create relationships from dimensions to `fct_transactions`.

## Data Privacy

Private transaction exports belong in `data/raw/` and are excluded from Git. The repository uses synthetic, non-identifying sample data for development and portfolio demonstration.

## Future Improvements

- Add budget inputs and budget-versus-actual reporting
- Add savings-goal and forecast modeling
- Expand source-standardization mappings as new sources appear
- Automate end-to-end refresh orchestration
- Add automated tests for transformation and quality rules
