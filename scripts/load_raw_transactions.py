from pathlib import Path
import re
import pandas as pd

# uses script current location to find project folder
PROJECT_ROOT = Path(__file__).resolve().parents[1]

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

if __name__ == "__main__":
    main()