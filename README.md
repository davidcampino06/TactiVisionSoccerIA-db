# TactiSoccerIA-db

[![CI](https://github.com/davidcampino06/TactiVisionSoccerIA-db/actions/workflows/ci.yml/badge.svg)](https://github.com/davidcampino06/TactiVisionSoccerIA-db/actions/workflows/ci.yml)

Integración continua (GitHub Actions, `.github/workflows/ci.yml`): en cada push a `main` y en cada
pull request se cargan el esquema y las migraciones (dos veces), y se prueban RLS, las reglas de
datos, la auditoría, el diccionario de datos, los datos de demostración y el respaldo con restauración.

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
`recommendation_indicators`, `reports`, `notifications` y `notification_reads` (migración 0004) y
`audit_log` (migración 0006). Cada tabla y columna está descrita en el
[diccionario de datos](docs/DICCIONARIO_DE_DATOS.md), con el diagrama entidad-relación.

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
| `0004_notifications.sql` | Notificaciones del equipo (la campana) y quién leyó cada una, con RLS por equipo y por usuario |
| `0005_proximity_network.sql` | Red de cercanía de cada análisis (grafo + BFS de la IA) guardada como JSON en `video_analyses.proximity_network` |
| `0006_audit_log.sql` | Auditoría: un trigger registra cada alta, cambio y borrado en las tablas principales (sin contraseñas) |
| `0007_data_constraints.sql` | Reglas de datos (`CHECK`): correo en minúsculas, hash bcrypt, estados válidos, fechas en orden, marcador coherente |
| `0008_query_indexes.sql` | Índices para las consultas más usadas por la app |
| `0009_report_views.sql` | Vistas de consulta (`v_match_summary`, `v_analysis_indicators`, `v_player_participation`, `v_open_issues`) que respetan RLS |
| `0010_data_dictionary.sql` | Descripción en español de cada tabla, columna y vista (`COMMENT ON`), base del diccionario de datos |
| `0011_recommendation_team.sql` | Equipo al que se refiere cada posible problema (`TEAM_A`, `TEAM_B` o `MATCH`) |
| `0012_analysis_team_colors.sql` | Color de camiseta de cada equipo en el análisis y advertencias sin límite de 255 caracteres |
| `0013_recommendation_explanation.sql` | Explicación de cada posible problema en lenguaje de fútbol y un cuadro real que lo muestra (JSON) |
| `0014_notification_delete.sql` | Eliminar notificaciones de la propia campana (`hidden_at`): el resto del equipo las sigue viendo |

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
- `notifications` se filtra por equipo como `matches`; en `notification_reads` cada usuario solo ve
  y escribe sus propias marcas de leído.
- `users`, `formations` (catálogo compartido) y `system_status` no tienen RLS.
- Trabajo del sistema (análisis en segundo plano, recuperación al reiniciar, búsqueda por código de
  invitación) usa `app.bypass_rls = 'on'`.
- Funciona con el pooler de Neon porque todo es `SET LOCAL` (dura solo la transacción).

Activación: aplicar la migración 0002 y luego poner `DATABASE_RLS=true` en el backend. Mientras la
variable esté apagada, la aplicación se comporta exactamente igual que antes.

Demostración para la exposición: pegar `sql/verify_rls.sql` en el SQL Editor de Neon (no modifica datos).

## Auditoría (migración 0006)

Cada `INSERT`, `UPDATE` y `DELETE` en `users`, `teams`, `players`, `matches`, `videos`,
`ai_recommendations`, `tactical_plays` y `reports` deja una fila en `audit_log`: tabla, fila, acción,
fecha, quién (`app.current_user_id`) y qué cambió. En un `UPDATE` solo se guardan las columnas que
cambiaron, con su valor anterior y el nuevo, y un `UPDATE` que no cambia nada no se registra.

- El hash de la contraseña nunca se copia: un cambio de contraseña queda como `"changed"`.
- Tampoco se copian los JSON grandes (`snapshot_data`, `configuration_data`).
- La aplicación no puede leer ni modificar `audit_log` (RLS sin políticas); solo escribe el trigger,
  que es `SECURITY DEFINER`. Se consulta desde Neon con el usuario dueño.

```sql
SELECT changed_at, action, changed_by, changed_fields FROM audit_log
WHERE table_name = 'matches' ORDER BY changed_at DESC LIMIT 20;
```

## Reglas de datos (migración 0007)

Las reglas que antes solo validaba el backend ahora también las cumple la base de datos, así que ni
un error del código ni un `INSERT` manual pueden guardar datos imposibles (un partido jugado sin
marcador, una confianza de 1,4, un correo con mayúsculas...). Cada regla se agrega `NOT VALID` y luego
se valida: si filas antiguas no la cumplen, la migración no falla, la regla protege las filas nuevas
y `sql/verify_data.sql` muestra cuántas hay que corregir.

## Diccionario de datos y diagrama entidad-relación

[`docs/DICCIONARIO_DE_DATOS.md`](docs/DICCIONARIO_DE_DATOS.md) tiene el diagrama entidad-relación
(Mermaid, GitHub lo dibuja) y, por cada tabla, sus columnas, tipos, valores por defecto,
descripción, reglas e índices. No se escribe a mano: se genera desde la base de datos, así que
siempre coincide con el esquema real. GitHub Actions lo vuelve a generar y falla si quedó
desactualizado.

```bash
DATABASE_URL="postgresql://..." python scripts/data_dictionary.py
```

## Datos de demostración

`sql/seed_demo.sql` crea el equipo **Atlético Demo** (código `DEMO-2026`) con entrenador, analista,
14 jugadores, 6 partidos (5 jugados y 1 programado), eventos y análisis en modo simulación con
indicadores, posibles problemas y red de cercanía. Sirve para mostrar todas las pantallas sin
esperar a que la IA procese un video.

| Cuenta | Rol | Contraseña |
|---|---|---|
| `entrenador.demo@tactivision.co` | Entrenador | `Pizarra#Tactica26` |
| `analista.demo@tactivision.co` | Analista | `Pizarra#Tactica26` |

```bash
psql "$DATABASE_URL" -f sql/seed_demo.sql          # se puede correr varias veces
psql "$DATABASE_URL" -f sql/seed_demo_remove.sql   # lo quita todo
```

Las contraseñas solo se guardan como hash bcrypt. Si los datos se cargan en producción, conviene
quitarlos (o cambiar esas contraseñas) después de la presentación.

## Comprobaciones

| Archivo | Qué hace | Modifica datos |
|---|---|---|
| `sql/verify_rls.sql` | Demostración de Row-Level Security | No |
| `sql/checks.sql` | Prueba con `ASSERT` la auditoría, que se rechacen 8 filas inválidas, las vistas y RLS a través de ellas | No (termina en `ROLLBACK`) |
| `sql/verify_data.sql` | Reporte de salud: reglas sin validar, análisis atascados, videos sin análisis, dorsales repetidos, cuentas sin equipo, tamaño de cada equipo | No (solo lectura) |

## Respaldo y restauración

```bash
DATABASE_URL="postgresql://..." python scripts/backup_database.py                      # backups/<fecha>/
DATABASE_URL="postgresql://..." python scripts/backup_database.py --restore backups/<fecha>
```

- El respaldo guarda un CSV por tabla, todos dentro de una misma transacción de solo lectura
  (`REPEATABLE READ`): reflejan el mismo instante aunque la app siga escribiendo.
- `manifest.json` anota la fecha, las migraciones aplicadas y las filas y el SHA-256 de cada archivo.
- La restauración solo se hace en una base vacía con las mismas migraciones (por ejemplo una rama
  nueva de Neon). Primero revisa el SHA-256 de cada archivo; luego carga las tablas padres antes que
  las hijas (orden calculado con las claves foráneas) en una sola transacción, y pide escribir el
  nombre de la base para confirmar.
- La carpeta `backups/` está en `.gitignore`: un respaldo tiene datos personales y nunca se sube.
