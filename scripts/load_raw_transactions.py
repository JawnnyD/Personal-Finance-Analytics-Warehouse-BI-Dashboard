# pythons command-line argument parser
from argparse import ArgumentParser
# support timestamps, file paths, regular expressions, and python import-path setup
from datetime import datetime, timezone
from pathlib import Path
import re
import sys

# pandas reads and holds the csv as a dataframe
# create_engine creates the SQLAlchemy connection factory
# text wraps the verification SQL query
import pandas as pd
from sqlalchemy import create_engine, text

# find repo root from script location
PROJECT_ROOT = Path(__file__).resolve().parents[1]

# make projects src folder importable
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from finance_warehouse.config import get_database_url

# required columns for V2 transactions
REQUIRED_V2_COLUMNS = [
    "source_transaction_id",
    "transaction_date",
    "source",
    "description",
    "category",
    "subcategory",
    "transaction_type",
    "amount",
    "person",
    "payment_method",
    "account_name",
    "related_transaction_id",
    "notes",
]

# normalize column names -> remove whitespace, lowercase, underscores
def normalize_column_name(column_name: str) -> str:
    normalized = column_name.strip().lower()
    normalized = normalized.replace("#", " number ")
    normalized = re.sub(r"[^a-z0-9]+", "_", normalized)
    return normalized.strip("_")


# parses command line input and returns PATH object
def get_input_path() -> Path:
    # create command line parser
    parser = ArgumentParser(
        description="Load a V2 transaction CSV into raw.transactions."
    )
    # defines required input option, converst supplied text into PATH
    parser.add_argument(
        "--input",
        required=True,
        type=Path,
        help="Path to the V2 CSV, relative to the project root or absolute.",
    )

    # reads what was supplied after script name
    arguments = parser.parse_args()
    input_path = arguments.input

    # relative paths interpreted from project root
    if not input_path.is_absolute():
        input_path = PROJECT_ROOT / input_path

    return input_path

# checks the dataframs headers after normalization
def validate_columns(transactions: pd.DataFrame) -> None:
    # checks duplicate column names
    duplicate_columns = transactions.columns[
        transactions.columns.duplicated()
    ].tolist()

    if duplicate_columns:
        raise ValueError(
            f"Duplicate column names after normalization: {duplicate_columns}"
        )

    # find what columns are missing from required vs actual
    missing_columns = sorted(
        set(REQUIRED_V2_COLUMNS) - set(transactions.columns)
    )

    if missing_columns:
        raise ValueError(
            "CSV is missing required V2 columns: "
            f"{', '.join(missing_columns)}"
        )


def main() -> None:
    # get requested csv path from --input
    input_path = get_input_path()

    # check if path exists before reading
    if not input_path.exists():
        raise FileNotFoundError(f"CSV not found: {input_path}")

    transactions = pd.read_csv(input_path, dtype="string")

    print(f"Loading source file: {input_path.name}")
    print(f"Row count: {len(transactions)}")

    print("\nOriginal column names:")
    print(transactions.columns.tolist())

    # normalize column names
    transactions.columns = [
        normalize_column_name(column_name)
        for column_name in transactions.columns
    ]

    print("\nNormalized column names:")
    print(transactions.columns.tolist())

    # validate columns
    validate_columns(transactions)

    print("\nFirst five rows:")
    print(transactions.head().to_string(index=False))

    print("\nMissing value counts:")
    print(transactions.isna().sum().to_string())

    # creates one UTC timestamp for entire load
    loaded_at = datetime.now(timezone.utc)

    # add file name, timestamp, records original csv row numbers
    transactions["source_file"] = input_path.name
    transactions["loaded_at"] = loaded_at
    transactions["raw_row_number"] = range(2, len(transactions) + 2)

    # builds sqlalchemy engine using project db connection
    engine = create_engine(get_database_url())

    # opens db connection and transaction
    with engine.begin() as connection:
        transactions.to_sql(
            name="transactions",
            con=connection,
            schema="raw",
            if_exists="replace",
            index=False,
        )

    with engine.connect() as connection:
        result = connection.execute(
            text(
                """
                SELECT
                    COUNT(*) AS row_count,
                    COUNT(DISTINCT source_transaction_id)
                        AS distinct_source_transaction_id_count
                FROM raw.transactions
                """
            )
        ).one()

    # early dupe check
    print("\nLoaded raw.transactions successfully.")
    print(f"Database row count: {result.row_count}")
    print(
        "Distinct source transaction IDs: "
        f"{result.distinct_source_transaction_id_count}"
    )


if __name__ == "__main__":
    main()