"""Apply pending migrations in order and record them in schema_migrations.

    pip install psycopg2-binary
    DATABASE_URL="postgresql://USER:PASSWORD@HOST/DB?sslmode=require" python scripts/apply_migrations.py

Order for a new database: sql/schema.sql first (baseline), then this script.
Each migration runs in its own transaction: if one fails, nothing of it is applied.
Use --list to see which migrations are applied and which are pending.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg2

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"


def migration_files() -> list[Path]:
    return sorted(MIGRATIONS_DIR.glob("[0-9][0-9][0-9][0-9]_*.sql"))


def main() -> int:
    url = os.getenv("DATABASE_URL")
    if not url:
        print("Set DATABASE_URL first.")
        return 1
    only_list = "--list" in sys.argv[1:]

    with psycopg2.connect(url) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations ("
                " version VARCHAR(100) PRIMARY KEY,"
                " applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
            )
            cursor.execute("SELECT version FROM schema_migrations")
            applied = {row[0] for row in cursor.fetchall()}
        connection.commit()

        pending = [path for path in migration_files() if path.stem not in applied]
        for path in migration_files():
            print(f"{'applied ' if path.stem in applied else 'PENDING '} {path.name}")
        if only_list or not pending:
            print("Nothing to apply." if not pending else "")
            return 0

        for path in pending:
            print(f"Applying {path.name} ...")
            try:
                with connection.cursor() as cursor:
                    cursor.execute(path.read_text(encoding="utf-8"))
                    cursor.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (path.stem,))
                connection.commit()
            except psycopg2.Error as error:
                connection.rollback()
                print(f"FAILED {path.name}: {error}")
                return 1
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
