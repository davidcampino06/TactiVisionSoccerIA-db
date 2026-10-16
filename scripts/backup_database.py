"""Back up every table to CSV files, and restore them into an empty database.

    pip install psycopg2-binary
    DATABASE_URL="postgresql://..." python scripts/backup_database.py                  # -> backups/<date>/
    DATABASE_URL="postgresql://..." python scripts/backup_database.py --restore backups/<date>

Backup
    One CSV per table (COPY ... TO STDOUT, with header) inside a single REPEATABLE READ, READ ONLY
    transaction, so every file shows the database at the same instant even if the app keeps writing.
    manifest.json records the date, the applied migrations, and the rows and SHA-256 of each file.
    The folder backups/ is in .gitignore: a backup holds personal data and password hashes, so it
    must never be committed.

Restore
    Only into a database that already has the schema and the same migrations, and whose tables are
    empty (a new Neon branch, for example). It checks every file against its SHA-256 first, then
    loads the tables parents first (order taken from the foreign keys) in one transaction: if any
    file fails, nothing is loaded. The audit triggers are switched off while loading, so the restore
    does not fill audit_log with copies of the data. It asks for the database name before writing.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
from psycopg2 import sql

BACKUPS_DIR = Path(__file__).resolve().parent.parent / "backups"

TABLES = """
SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY c.relname
"""
FOREIGN_KEYS = """
SELECT cl.relname, ref.relname, a.attname, NOT a.attnotnull FROM pg_constraint con
JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = con.conkey[1]
JOIN pg_class cl ON cl.oid = con.conrelid
JOIN pg_class ref ON ref.oid = con.confrelid
JOIN pg_namespace n ON n.oid = cl.relnamespace
WHERE n.nspname = 'public' AND con.contype = 'f' AND cl.oid <> ref.oid
"""
SEQUENCES = """
SELECT c.relname, a.attname, pg_get_serial_sequence(quote_ident(c.relname), a.attname)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND pg_get_serial_sequence(quote_ident(c.relname), a.attname) IS NOT NULL
"""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def load_order(tables: list[str], edges: list[tuple[str, str]]) -> list[str]:
    """Parents before children (Kahn's algorithm over the foreign keys). Ties in name order."""
    parents: dict[str, set[str]] = {table: set() for table in tables}
    for child, parent in edges:
        if child in parents and parent in parents:
            parents[child].add(parent)
    order: list[str] = []
    ready = sorted(table for table, needed in parents.items() if not needed)
    while ready:
        table = ready.pop(0)
        order.append(table)
        for child, needed in parents.items():
            if table in needed:
                needed.discard(table)
                if not needed and child not in order and child not in ready:
                    ready.append(child)
        ready.sort()
    if len(order) != len(tables):
        raise RuntimeError("The foreign keys form a cycle; cannot choose a load order.")
    return order


def backup(url: str, target: Path) -> int:
    target.mkdir(parents=True, exist_ok=False)
    files = {}
    with psycopg2.connect(url) as connection:
        connection.set_session(isolation_level="REPEATABLE READ", readonly=True)
        with connection.cursor() as cursor:
            cursor.execute(TABLES)
            tables = [row[0] for row in cursor.fetchall()]
            cursor.execute("SELECT version FROM schema_migrations ORDER BY version")
            migrations = [row[0] for row in cursor.fetchall()]
            for table in tables:
                path = target / f"{table}.csv"
                with path.open("w", encoding="utf-8", newline="") as handle:
                    cursor.copy_expert(
                        sql.SQL("COPY {} TO STDOUT WITH (FORMAT csv, HEADER true)").format(sql.Identifier(table)), handle)
                with path.open(encoding="utf-8", newline="") as handle:
                    rows = max(0, sum(1 for _ in csv.reader(handle)) - 1)
                files[table] = {"file": path.name, "rows": rows, "sha256": sha256(path)}
                print(f"  {table:<28} {rows:>7} filas")
    manifest = {
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "migrations": migrations,
        "tables": files,
    }
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Backup written to {target} ({len(files)} tables, {sum(f['rows'] for f in files.values())} rows).")
    return 0


def copy_into(cursor, table: str, path: Path, deferred: list[str]) -> None:
    """COPY one CSV into its table. Columns in ``deferred`` are left NULL and kept in a temporary
    table (restore_<table>) so they can be filled once the rows they point to exist."""
    with path.open(encoding="utf-8", newline="") as handle:
        header = next(csv.reader(io.StringIO(handle.readline())))
        handle.seek(0)
        columns = sql.SQL(", ").join(map(sql.Identifier, header))
        if not deferred:
            cursor.copy_expert(sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT csv, HEADER true)").format(
                sql.Identifier(table), columns), handle)
            return
        staging = sql.Identifier(f"restore_{table}")
        cursor.execute(sql.SQL("CREATE TEMP TABLE {} (LIKE {}) ON COMMIT DROP").format(staging, sql.Identifier(table)))
        cursor.copy_expert(sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT csv, HEADER true)").format(staging, columns), handle)
        values = sql.SQL(", ").join(sql.SQL("NULL") if name in deferred else sql.Identifier(name) for name in header)
        cursor.execute(sql.SQL("INSERT INTO {} ({}) SELECT {} FROM {}").format(sql.Identifier(table), columns, values, staging))


def restore(url: str, source: Path, assume_yes: bool) -> int:
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    for table, entry in manifest["tables"].items():
        if sha256(source / entry["file"]) != entry["sha256"]:
            print(f"{entry['file']} does not match its SHA-256 in manifest.json. Nothing restored.")
            return 1

    with psycopg2.connect(url) as connection, connection.cursor() as cursor:
        cursor.execute("SELECT current_database()")
        database = cursor.fetchone()[0]
        cursor.execute("SELECT version FROM schema_migrations ORDER BY version")
        migrations = [row[0] for row in cursor.fetchall()]
        if migrations != manifest["migrations"]:
            print("The target database has different migrations than the backup:")
            print(f"  backup: {manifest['migrations']}\n  target: {migrations}")
            return 1
        cursor.execute(TABLES)
        tables = [row[0] for row in cursor.fetchall() if row[0] in manifest["tables"]]
        busy = []
        for table in tables:
            cursor.execute(sql.SQL("SELECT EXISTS (SELECT 1 FROM {})").format(sql.Identifier(table)))
            if cursor.fetchone()[0] and table not in ("schema_migrations", "system_status"):
                busy.append(table)
        if busy:
            print(f"These tables already have data: {', '.join(busy)}. Restore only into an empty database.")
            return 1

        if not assume_yes:
            answer = input(f"Restore {source.name} into database '{database}'? Type its name to confirm: ")
            if answer.strip() != database:
                print("Cancelled.")
                return 1

        # teams.coach_id -> users and users.team_id -> teams form a cycle. The order ignores the
        # optional (nullable) foreign keys; those columns are loaded empty and filled at the end.
        cursor.execute(FOREIGN_KEYS)
        keys = cursor.fetchall()
        order = load_order(tables, [(child, parent) for child, parent, _, optional in keys if not optional])
        position = {table: index for index, table in enumerate(order)}
        later = {}
        for child, parent, column, optional in keys:
            if optional and child in position and parent in position and position[parent] > position[child]:
                later.setdefault(child, []).append(column)

        for table in order:
            if table in ("schema_migrations", "system_status"):
                continue  # created by the schema and the migrations themselves
            entry = manifest["tables"][table]
            cursor.execute(sql.SQL("ALTER TABLE {} DISABLE TRIGGER USER").format(sql.Identifier(table)))
            copy_into(cursor, table, source / entry["file"], later.get(table, []))
            cursor.execute(sql.SQL("ALTER TABLE {} ENABLE TRIGGER USER").format(sql.Identifier(table)))
            print(f"  {table:<28} {entry['rows']:>7} filas")

        for table, columns in later.items():
            cursor.execute(sql.SQL("ALTER TABLE {} DISABLE TRIGGER USER").format(sql.Identifier(table)))
            cursor.execute(sql.SQL("UPDATE {} AS t SET {} FROM {} AS s WHERE t.id = s.id").format(
                sql.Identifier(table),
                sql.SQL(", ").join(sql.SQL("{} = s.{}").format(sql.Identifier(c), sql.Identifier(c)) for c in columns),
                sql.Identifier(f"restore_{table}")))
            cursor.execute(sql.SQL("ALTER TABLE {} ENABLE TRIGGER USER").format(sql.Identifier(table)))

        # Serial columns (audit_log.id) continue after the restored rows.
        cursor.execute(SEQUENCES)
        for table, column, sequence in cursor.fetchall():
            cursor.execute(
                sql.SQL("SELECT setval(%s, coalesce((SELECT max({}) FROM {}), 0) + 1, false)").format(
                    sql.Identifier(column), sql.Identifier(table)), (sequence,))
    print(f"Restored {source.name} into '{database}'.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--restore", type=Path, metavar="FOLDER", help="backup folder to load")
    parser.add_argument("--yes", action="store_true", help="do not ask for confirmation (automatic tests)")
    parser.add_argument("--output", type=Path, help="backup folder (default backups/<UTC date and time>)")
    args = parser.parse_args()

    url = os.getenv("DATABASE_URL")
    if not url:
        print("Set DATABASE_URL first.")
        return 1
    if args.restore:
        return restore(url, args.restore, args.yes)
    target = args.output or BACKUPS_DIR / datetime.now(timezone.utc).strftime("%Y-%m-%d_%H%M%S")
    return backup(url, target)


if __name__ == "__main__":
    sys.exit(main())
