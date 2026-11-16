"""Apply pending migrations in order and record them in schema_migrations.

    pip install psycopg2-binary
    DATABASE_URL="postgresql://USER:PASSWORD@HOST/DB?sslmode=require" python scripts/apply_migrations.py

Order for a new database: sql/schema.sql first (baseline), then this script.
Each migration runs in its own transaction: if one fails, nothing of it is applied.
Use --list to see which migrations are applied and which are pending.

Since migration 0027 each applied migration keeps the SHA-256 of its file. If a file changed after it
was applied, the script says which one and stops without applying anything: a migration that already
ran is never edited, a new one is written instead. --accept-changes records the new fingerprints
(only when the change is harmless, e.g. a comment). Migrations applied before 0027 get their
fingerprint the first time the script runs after it.
"""

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path

import psycopg2

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"


def migration_files() -> list[Path]:
    return sorted(MIGRATIONS_DIR.glob("[0-9][0-9][0-9][0-9]_*.sql"))


def checksum(path: Path) -> str:
    """SHA-256 of the file with Windows line endings turned into Unix ones (same value on every OS)."""
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def has_checksum_column(cursor) -> bool:
    cursor.execute("SELECT 1 FROM information_schema.columns "
                   "WHERE table_name = 'schema_migrations' AND column_name = 'checksum'")
    return cursor.fetchone() is not None


def main() -> int:
    url = os.getenv("DATABASE_URL")
    if not url:
        print("Set DATABASE_URL first.")
        return 1
    only_list = "--list" in sys.argv[1:]
    accept_changes = "--accept-changes" in sys.argv[1:]

    with psycopg2.connect(url) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations ("
                " version VARCHAR(100) PRIMARY KEY,"
                " applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
            )
            tracked = has_checksum_column(cursor)
            cursor.execute("SELECT version, checksum FROM schema_migrations" if tracked
                           else "SELECT version, NULL FROM schema_migrations")
            applied = dict(cursor.fetchall())
        connection.commit()

        files = migration_files()
        changed = [path for path in files if applied.get(path.stem) and applied[path.stem] != checksum(path)]
        pending = [path for path in files if path.stem not in applied]
        for path in files:
            state = "PENDING " if path.stem not in applied else "CHANGED " if path in changed else "applied "
            print(f"{state} {path.name}")
        if changed and not accept_changes:
            print("\nThese migrations were edited after being applied: "
                  + ", ".join(path.name for path in changed)
                  + ".\nUndo the edit and write a new migration instead (or run with --accept-changes "
                    "if the change is harmless, like a comment). Nothing was applied.")
            return 1
        if only_list:
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

        # Fingerprints: new migrations, the ones applied before 0027, and accepted changes.
        with connection.cursor() as cursor:
            if has_checksum_column(cursor):
                cursor.execute("SELECT version, checksum FROM schema_migrations")
                stored = dict(cursor.fetchall())
                recorded = 0
                for path in files:
                    if path.stem in stored and stored[path.stem] != checksum(path):
                        cursor.execute("UPDATE schema_migrations SET checksum = %s WHERE version = %s",
                                       (checksum(path), path.stem))
                        recorded += 1
                if recorded:
                    print(f"Recorded the fingerprint of {recorded} migration(s).")
        connection.commit()
    print("Nothing to apply." if not pending else "Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
