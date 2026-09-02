from pathlib import Path
from datetime import datetime, timezone
from sqlalchemy import create_engine, text

import re
import pandas as pd
import sys


# uses script current location to find project folder
PROJECT_ROOT = Path(__file__).resolve().parents[1]

# add src to search path for importing modules
sys.path.insert(0, str(PROJECT_ROOT / "src"))

# must come after src is added to search path
from finance_warehouse.config import get_database_url

# join path components to find csv in /data/raw/...
RAW_CSV_PATH = (
    PROJECT_ROOT
    / "data"
    / "raw"
    / "transactions_raw_2026-09-01.csv"
)

# normalize column names by strip whitespace, replacing # w/ 'number', replacing other special characters with '_', then strip '_'
def normalize_column_name(column_name: str) -> str:
    normalized = column_name.strip().lower()
    normalized = normalized.replace("#", " number ")
    normalized = re.sub(r"[^a-z0-9]+", "_", normalized)
    return normalized.strip("_")

# script to load and normalize column names
def main() -> None:
    # if raw csv path doesnt exist, raise error
    if not RAW_CSV_PATH.exists():
        raise FileNotFoundError(f"Raw CSV not found: {RAW_CSV_PATH}")

    # read csv with values as strings
    transactions = pd.read_csv(RAW_CSV_PATH, dtype="string")

    print(f"Row count: {len(transactions)}")

    print("\nOriginal column names:")
    print(transactions.columns.tolist())

    # list all column names, then run normalization on all of them
    transactions.columns = [
        normalize_column_name(column_name)
        for column_name in transactions.columns
    ]

    print("\nNormalized column names:")
    print(transactions.columns.tolist())

    print("\nFirst five rows:")
    print(transactions.head().to_string(index=False))

    print("\nMissing value counts:")
    print(transactions.isna().sum().to_string())

    # create timestamp for when data was loaded
    loaded_at = datetime.now(timezone.utc)

    # add new columns to dataframe with respective data
    transactions["source_file"] = RAW_CSV_PATH.name
    transactions["loaded_at"] = loaded_at
    transactions["raw_row_number"] = range(2, len(transactions) + 2)

    # creates SQLAlchemy database engine for pandas and SQLAlchemy to talk to database
    engine = create_engine(get_database_url())

    # opens db connection and starts transaction, writes pandas DataFrame into SQL db table
    with engine.begin() as connection:
        transactions.to_sql(
            name = "transactions",
            con = connection,
            schema = "raw",
            if_exists = "replace",
            index = False,
        )

    # opens normal db connection to read row count
    # unlike engine.begin, does not automatically start transactions for a write operation.
    with engine.connect() as connection:
        database_row_count = connection.execute(
            text("SELECT COUNT(*) FROM raw.transactions")
        ).scalar_one()

    print("\nLoaded raw.transactions successfully.")
    print(f"Database row count: {database_row_count}")

if __name__ == "__main__":
    main()
