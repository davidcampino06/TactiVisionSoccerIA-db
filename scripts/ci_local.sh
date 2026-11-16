#!/usr/bin/env bash
# Runs the steps of .github/workflows/ci.yml on a local PostgreSQL, before pushing.
#
#     ADMIN_URL=postgresql://postgres:postgres@localhost:5432/postgres bash scripts/ci_local.sh
#
# It creates (and drops first) two scratch databases, tactivision_ci and tactivision_restore, on the
# server of ADMIN_URL: never point it at Neon or any database with real data. Needs psql, Python and
# psycopg2. Stops at the first step that fails, like the CI.
set -euo pipefail
cd "$(dirname "$0")/.."

ADMIN_URL="${ADMIN_URL:-postgresql://postgres:postgres@localhost:5432/postgres}"
BASE="${ADMIN_URL%/*}"
export DATABASE_URL="$BASE/tactivision_ci"
RESTORE_URL="$BASE/tactivision_restore"
PYTHON="${PYTHON:-python3}"
step() { printf '\n== %s\n' "$1"; }
cleanup() { git checkout -q -- migrations/0001_schema_migrations.sql 2>/dev/null || true; rm -rf backups/local edited.log; }
trap cleanup EXIT

psql -q "$ADMIN_URL" -c "DROP DATABASE IF EXISTS tactivision_restore" -c "DROP DATABASE IF EXISTS tactivision_ci" \
     -c "CREATE DATABASE tactivision_ci"

step "1. Esquema base"
psql -q -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sql/schema.sql > /dev/null
step "2. Aplicar migraciones"
"$PYTHON" scripts/apply_migrations.py | tail -1
step "3. Segunda ejecución sin pendientes"
"$PYTHON" scripts/apply_migrations.py | grep -q "Nothing to apply." && echo OK
step "3b. Una migración editada se detecta"
echo "-- editada" >> migrations/0001_schema_migrations.sql
if "$PYTHON" scripts/apply_migrations.py > edited.log; then echo "no se detectó el cambio"; exit 1; fi
grep -q "CHANGED  0001_schema_migrations.sql" edited.log
git checkout -q -- migrations/0001_schema_migrations.sql
sed -i 's/$/\r/' migrations/0001_schema_migrations.sql
"$PYTHON" scripts/apply_migrations.py | grep -q "Nothing to apply."
git checkout -q -- migrations/0001_schema_migrations.sql && echo OK
step "4. Migraciones idempotentes"
for migration in migrations/*.sql; do psql -q -v ON_ERROR_STOP=1 "$DATABASE_URL" -f "$migration" > /dev/null; done && echo OK
step "5. Demostración de Row-Level Security"
psql -q -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sql/verify_rls.sql > /dev/null && echo OK
step "6. Reglas, auditoría y vistas"
psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sql/checks.sql 2>&1 | grep -o "OK .*"
step "7. Diccionario de datos al día"
"$PYTHON" scripts/data_dictionary.py > /dev/null
git diff --exit-code --stat docs/DICCIONARIO_DE_DATOS.md && echo OK
step "8. Datos de demostración (dos veces) y reporte de salud"
psql -q -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sql/seed_demo.sql > /dev/null
psql -q -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sql/seed_demo.sql > /dev/null
test "$(psql -At "$DATABASE_URL" -c "SELECT count(*) FROM players WHERE team_id = 'demo-team'")" = 14
psql -q -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sql/verify_data.sql > /dev/null && echo OK
step "9. Respaldo y restauración (con una foto binaria)"
psql -q -v ON_ERROR_STOP=1 "$DATABASE_URL" -c "INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image) SELECT id, 1, 0, 0, 0.9, 20, 40, decode('ffd8ffe000104a4649460001', 'hex') FROM video_analyses WHERE id = 'demo-analysis-5'"
"$PYTHON" scripts/backup_database.py --output backups/local > /dev/null
psql -q "$ADMIN_URL" -c "CREATE DATABASE tactivision_restore"
psql -q -v ON_ERROR_STOP=1 "$RESTORE_URL" -f sql/schema.sql > /dev/null
DATABASE_URL="$RESTORE_URL" "$PYTHON" scripts/apply_migrations.py > /dev/null
DATABASE_URL="$RESTORE_URL" "$PYTHON" scripts/backup_database.py --restore backups/local --yes > /dev/null
for table in users teams players matches videos video_analyses detections tactical_indicators track_snapshots audit_log; do
    query="SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY t::text), '')) FROM $table t"
    test "$(psql -At "$DATABASE_URL" -c "$query")" = "$(psql -At "$RESTORE_URL" -c "$query")" \
        || { echo "$table differs after the restore"; exit 1; }
done && echo OK
step "10. Quitar los datos de demostración"
psql -q -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sql/seed_demo_remove.sql > /dev/null
test "$(psql -At "$DATABASE_URL" -c "SELECT (SELECT count(*) FROM teams WHERE id = 'demo-team') + (SELECT count(*) FROM players WHERE id LIKE 'demo-%') + (SELECT count(*) FROM users WHERE id LIKE 'demo-%')")" = 0 && echo OK

printf '\nTodo pasó: es lo mismo que revisa GitHub Actions.\n'
