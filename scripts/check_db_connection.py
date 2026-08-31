import sys
from pathlib import Path

from sqlalchemy import create_engine, text

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from finance_warehouse.config import get_database_url


def main() -> int:
    engine = create_engine(get_database_url())

    with engine.connect() as connection:
        database_name = connection.execute(text("SELECT current_database();")).scalar_one()
        schemas = list(
            connection.execute(
                text(
                    """
                    SELECT schema_name
                    FROM information_schema.schemata
                    WHERE schema_name IN ('raw', 'staging', 'marts', 'quality')
                    ORDER BY schema_name;
                    """
                )
            ).scalars()
        )

    print(f"Connected to database: {database_name}")
    print(f"Project schemas found: {', '.join(schemas)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
