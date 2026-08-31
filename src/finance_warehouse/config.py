import os

from dotenv import load_dotenv
from sqlalchemy import URL


def get_database_url() -> str:
    load_dotenv()
    database_url = os.getenv("DATABASE_URL")

    if database_url:
        return database_url

    required_vars = ["PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"]
    missing_vars = [name for name in required_vars if not os.getenv(name)]

    if missing_vars:
        missing = ", ".join(missing_vars)
        raise RuntimeError(
            f"Missing database config: {missing}. Create a .env file using .env.example."
        )

    return str(
        URL.create(
            "postgresql+psycopg",
            username=os.environ["PGUSER"],
            password=os.environ["PGPASSWORD"],
            host=os.environ["PGHOST"],
            port=int(os.environ["PGPORT"]),
            database=os.environ["PGDATABASE"],
        )
    )
