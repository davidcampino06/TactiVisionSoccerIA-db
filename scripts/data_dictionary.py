"""Write the data dictionary and the ER diagram from the database itself.

    DATABASE_URL="postgresql://..." python scripts/data_dictionary.py            # -> docs/DICCIONARIO_DE_DATOS.md
    DATABASE_URL="postgresql://..." python scripts/data_dictionary.py --stdout   # print it instead

Everything comes from the catalog, so the document never drifts from the real schema:
descriptions from COMMENT ON (migration 0010), columns and types of tables and views from
information_schema, keys, CHECK rules and indexes from pg_catalog. The ER diagram is Mermaid, which GitHub draws.
"""

from __future__ import annotations

import os
import sys
from collections import defaultdict
from pathlib import Path

import psycopg2

OUTPUT = Path(__file__).resolve().parent.parent / "docs" / "DICCIONARIO_DE_DATOS.md"
SKIP = {"schema_migrations", "system_status"}

TABLES = """
SELECT c.relname, obj_description(c.oid, 'pg_class'), c.relkind
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v')
ORDER BY c.relkind DESC, c.relname
"""
COLUMNS = """
SELECT c.table_name, c.column_name,
       CASE WHEN c.data_type = 'character varying' THEN 'varchar(' || c.character_maximum_length || ')'
            WHEN c.data_type = 'numeric' AND c.numeric_precision IS NOT NULL
                 THEN 'numeric(' || c.numeric_precision || ',' || c.numeric_scale || ')'
            WHEN c.data_type = 'timestamp without time zone' THEN 'timestamp'
            ELSE c.data_type END,
       c.is_nullable = 'YES', c.column_default,
       col_description((quote_ident(c.table_schema) || '.' || quote_ident(c.table_name))::regclass, c.ordinal_position)
FROM information_schema.columns c
WHERE c.table_schema = 'public'
ORDER BY c.table_name, c.ordinal_position
"""
CONSTRAINTS = """
SELECT cl.relname, con.conname, con.contype, pg_get_constraintdef(con.oid), con.convalidated,
       ref.relname,
       ARRAY(SELECT a.attname FROM unnest(con.conkey) k JOIN pg_attribute a
             ON a.attrelid = con.conrelid AND a.attnum = k)
FROM pg_constraint con
JOIN pg_class cl ON cl.oid = con.conrelid
JOIN pg_namespace n ON n.oid = cl.relnamespace
LEFT JOIN pg_class ref ON ref.oid = con.confrelid
WHERE n.nspname = 'public'
ORDER BY cl.relname, con.contype, con.conname
"""
POLICIES = """
SELECT tablename, policyname, cmd, qual FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename, policyname
"""
RLS_ENABLED = """
SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity
"""
# Functions of the project only: those created by an extension (pg_depend 'e') are left out.
FUNCTIONS = """
SELECT p.proname, pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid),
       CASE p.provolatile WHEN 'i' THEN 'IMMUTABLE' WHEN 's' THEN 'STABLE' ELSE 'VOLATILE' END,
       obj_description(p.oid, 'pg_proc')
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f'
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
ORDER BY p.proname
"""
# Triggers written by the project (not the internal ones of foreign keys), with their arguments:
# the audit trigger receives the key columns that name a row (migration 0031).
TRIGGERS = """
SELECT cl.relname, t.tgname, pg_get_triggerdef(t.oid)
FROM pg_trigger t
JOIN pg_class cl ON cl.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = cl.relnamespace
WHERE n.nspname = 'public' AND NOT t.tgisinternal
ORDER BY cl.relname, t.tgname
"""
INDEXES = """
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename, indexname
"""


def fetch(cursor, sql):
    cursor.execute(sql)
    return cursor.fetchall()


def build(url: str) -> str:
    with psycopg2.connect(url) as connection, connection.cursor() as cursor:
        tables = fetch(cursor, TABLES)
        columns = defaultdict(list)
        for table, *rest in fetch(cursor, COLUMNS):
            columns[table].append(rest)
        constraints = defaultdict(list)
        for table, *rest in fetch(cursor, CONSTRAINTS):
            constraints[table].append(rest)
        indexes = defaultdict(list)
        for table, name, definition in fetch(cursor, INDEXES):
            indexes[table].append((name, definition))
        policies = defaultdict(list)
        for table, *rest in fetch(cursor, POLICIES):
            policies[table].append(rest)
        rls_enabled = {row[0] for row in fetch(cursor, RLS_ENABLED)}
        triggers = defaultdict(list)
        for table, name, definition in fetch(cursor, TRIGGERS):
            triggers[table].append((name, definition))
        functions = fetch(cursor, FUNCTIONS)

    real_tables = [(name, text) for name, text, kind in tables if kind == "r" and name not in SKIP]
    views = [(name, text) for name, text, kind in tables if kind == "v"]
    out = ["# Diccionario de datos · TactiVision IA", "",
           "> Generado con `scripts/data_dictionary.py` a partir de la base de datos (esquema + migraciones).",
           "> No se edita a mano: si cambia el esquema, se vuelve a generar.", "",
           f"{len(real_tables)} tablas y {len(views)} vistas.", "", "## Diagrama entidad-relación", "",
           "```mermaid", "erDiagram"]

    for table, _ in real_tables:
        keys = {tuple(cols): kind for _, kind, _, _, _, cols in constraints[table] if kind in ("p", "f")}
        out.append(f"    {table} {{")
        for name, data_type, _nullable, _default, _comment in columns[table]:
            mark = "PK" if keys.get((name,)) == "p" else "FK" if keys.get((name,)) == "f" else ""
            if mark or name in ("name", "email", "status", "role", "match_date", "value", "severity"):
                out.append(f"        {data_type.split('(')[0].replace(' ', '_')} {name} {mark}".rstrip())
        out.append("    }")
    for table, _ in real_tables:
        for _, kind, _, _, referenced, cols in constraints[table]:
            if kind == "f" and referenced:
                nullable = any(n == cols[0] and is_null for n, _, is_null, _, _ in columns[table])
                left = "|o" if nullable else "||"
                out.append(f'    {referenced} {left}--o{{ {table} : "{cols[0]}"')
    out += ["```", ""]

    out += ["## Tablas", ""]
    for table, text in real_tables:
        out += [f"### `{table}`", "", text or "", "", "| Columna | Tipo | Nulo | Por defecto | Descripción |",
                "|---|---|---|---|---|"]
        for name, data_type, nullable, default, comment in columns[table]:
            default = (default or "").replace("::character varying", "").replace("|", "\\|")
            out.append(f"| `{name}` | {data_type} | {'sí' if nullable else 'no'} | {default} | {comment or ''} |")
        rules = []
        for name, kind, definition, validated, referenced, cols in constraints[table]:
            label = {"p": "Clave primaria", "f": f"Clave foránea → `{referenced}`", "u": "Único", "c": "Regla"}.get(kind, kind)
            note = "" if validated else " *(NOT VALID: solo filas nuevas)*"
            rules.append(f"- {label}: `{definition}`{note}")
        if rules:
            out += ["", "**Reglas**", "", *rules]
        extra = [f"- `{name}`: `{definition.split(' USING ')[-1]}`" for name, definition in indexes[table]
                 if not name.endswith("_pkey") and "UNIQUE" not in definition]
        if extra:
            out += ["", "**Índices**", "", *extra]
        if triggers[table]:
            out += ["", "**Disparadores**", ""]
            out += [f"- `{name}`: `{definition.split(' ON ')[0].split(name, 1)[-1].strip()}` → "
                    f"`{definition.split('EXECUTE FUNCTION ')[-1]}`" for name, definition in triggers[table]]
        if table in rls_enabled:
            # Row-Level Security (migration 0002 and later): who can see or change each row.
            out += ["", "**Seguridad por filas (RLS)**", ""]
            out += [f"- `{name}` ({command}): `{(rule or 'true').replace(chr(10), ' ')}`"
                    for name, command, rule in policies[table]] or ["- Activa sin políticas: nadie ve filas salvo el dueño."]
        out.append("")

    out += ["## Vistas", "", "| Vista | Qué muestra |", "|---|---|"]
    out += [f"| `{name}` | {text or ''} |" for name, text in views]
    # The columns of each view, so a report can be written from this document alone.
    for name, _ in views:
        out += ["", f"### `{name}`", "", "| Columna | Tipo |", "|---|---|"]
        out += [f"| `{column}` | {data_type} |" for column, data_type, *_ in columns[name]]

    out += ["", "## Funciones", "", "Funciones propias de la base (las de extensiones no se listan).", "",
            "| Función | Devuelve | Volatilidad | Qué hace |", "|---|---|---|---|"]
    out += [f"| `{name}({arguments})` | {result} | {volatility} | {comment or ''} |"
            for name, arguments, result, volatility, comment in functions]
    return "\n".join(out) + "\n"


def main() -> int:
    url = os.getenv("DATABASE_URL")
    if not url:
        print("Set DATABASE_URL first.")
        return 1
    document = build(url)
    if "--stdout" in sys.argv[1:]:
        print(document)
        return 0
    OUTPUT.parent.mkdir(exist_ok=True)
    OUTPUT.write_text(document, encoding="utf-8")
    print(f"Written {OUTPUT.relative_to(OUTPUT.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
