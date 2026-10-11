# TactiSoccerIA-db

Esquema PostgreSQL de TactiVision IA basado en el **TactiVision Database ERD**.

`sql/schema.sql` es **idempotente**: usa `CREATE ... IF NOT EXISTS`, no borra tablas ni datos y
conserva `system_status` (usada por `GET /api/status`). Se puede ejecutar sobre la base actual de Neon.

```bash
psql "postgresql://USER:PASSWORD@HOST/DB?sslmode=require" -f sql/schema.sql
```
(En Neon también se puede pegar en el SQL Editor.)

## Tablas
`system_status`, `users`, `teams`, `players`, `player_team_history`, `matches`, `match_events`,
`formations`, `match_formations`, `tactical_plays`, `tactical_play_versions`, `match_tactical_plays`,
`videos`, `video_analyses`, `detections`, `tactical_indicators`, `ai_recommendations`,
`recommendation_indicators`, `reports`.

## Desviaciones mínimas respecto al ERD (justificadas)

| Cambio | Motivo |
|---|---|
| `teams.invitation_code` (UNIQUE) | Ingreso de analistas con código tipo `BARCA-7K29` |
| `detections.track_id` | Identidad temporal de ByteTrack (necesaria para trayectorias y corrección manual) |
| `video_analyses.analysis_mode` | Distinguir `REAL_VIDEO_ANALYSIS` de `SIMULATION_MODE` sin mezclar datos |
| `TEXT` en `tactical_play_versions.configuration_data` y `reports.snapshot_data` | Guardan documentos JSON que superan 255 caracteres |
| `users.updated_at` | El ERD muestra la errata `update_at` |
| `bit` → `BOOLEAN`; `teams.coach_id` UNIQUE | Tipo nativo de PostgreSQL; regla "un coach, un equipo" |

## Migraciones

Los cambios al esquema se guardan como migraciones numeradas en `migrations/`. Cada una se aplica
una sola vez, en orden, y queda registrada en la tabla `schema_migrations`.

| Migración | Qué hace |
|---|---|
| `0001_schema_migrations.sql` | Tabla con el historial de migraciones aplicadas |
| `0002_row_level_security.sql` | Row-Level Security: PostgreSQL solo entrega las filas del equipo de quien consulta |
| `0003_player_details.sql` | Pie hábil del jugador (`preferred_foot`: RIGHT, LEFT o BOTH) |

Base nueva: primero `sql/schema.sql` y luego las migraciones.

```bash
pip install psycopg2-binary
DATABASE_URL="postgresql://USER:PASSWORD@HOST/DB?sslmode=require" python scripts/apply_migrations.py
python scripts/apply_migrations.py --list   # ver aplicadas y pendientes
```

## Row-Level Security (aislamiento entre equipos)

Es la segunda barrera de seguridad (la primera es la API). Aunque el backend tuviera un error y
consultara sin filtrar por equipo, la base de datos no devolvería filas de otro equipo.

- El rol `tactivision_app` **no puede saltarse RLS**. El backend cambia a ese rol en cada
  transacción (`SET LOCAL ROLE`) y le dice a PostgreSQL quién consulta:
  `app.current_user_id`, `app.current_role`, `app.current_team_id`.
- Tablas con `team_id` (`players`, `matches`, `tactical_plays`, `reports`, ...) comparan contra
  `app.current_team_id`. Las tablas hijas heredan la regla de su padre:
  equipo → partido → video → análisis → detecciones.
- El administrador solo puede **leer** los datos generales de `teams`; nada táctico.
- `users`, `formations` (catálogo compartido) y `system_status` no tienen RLS.
- Trabajo del sistema (análisis en segundo plano, recuperación al reiniciar, búsqueda por código de
  invitación) usa `app.bypass_rls = 'on'`.
- Funciona con el pooler de Neon porque todo es `SET LOCAL` (dura solo la transacción).

Activación: aplicar la migración 0002 y luego poner `DATABASE_RLS=true` en el backend. Mientras la
variable esté apagada, la aplicación se comporta exactamente igual que antes.

Demostración para la exposición: pegar `sql/verify_rls.sql` en el SQL Editor de Neon (no modifica datos).
