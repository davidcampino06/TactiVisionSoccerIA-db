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
| `0015_team_crest_and_kit.sql` | Escudo del equipo (`team_crests`), color habitual de la camiseta y cuál equipo detectado es el tuyo en cada análisis |
| `0016_player_availability.sql` | Disponibilidad del jugador: estado "no disponible" (motivo personal u otro), motivo de la ausencia, fecha estimada de regreso y aviso en la campana ese día |
| `0017_analysis_strengths.sql` | Lo que el equipo hizo bien en cada análisis (fortalezas): título, evidencia, confianza y explicación en lenguaje de fútbol, con RLS por análisis |
| `0018_review_notes_and_strengths.sql` | Notas del cuerpo técnico sobre cada posible problema (`recommendation_notes`, con RLS y aviso en la campana) y revisión de las fortalezas (`analysis_strengths.status`): el plan de partido solo usa lo confirmado |
| `0019_indicator_samples.sql` | Cuántos cuadros pudo juzgar cada indicador (`samples`) y qué proporción quedó del lado malo del umbral (`exceed_ratio`): el seguimiento de un problema confirmado distingue "no apareció" de "no se pudo juzgar" |
| `0020_video_situation.sql` | Situación táctica de cada clip, elegida por una persona (`videos.situation`: salida de balón, ataque organizado, transiciones, presión alta, bloque defensivo, balón parado) y una nota corta: la biblioteca de clips los filtra por situación |
| `0021_track_snapshots.sql` | Foto de cada trayectoria detectada (`track_snapshots`: el mejor recorte del video, JPEG pequeño, con RLS por análisis) para que el cuerpo técnico reconozca al jugador y lo vincule a la plantilla; los análisis anteriores no tienen fotos |
| `0022_team_action_types.sql` | Tipos de acción escritos por el equipo (`team_action_types`, únicos por equipo, con RLS) y límites de las jugadas nuevas: nombre de 50 caracteres y descripción de 100 |
| `0023_track_labels.sql` | Trayectorias que una persona marca como árbitro u otra persona externa (`track_labels`, con RLS por análisis); quedan fuera de la identificación y del ranking |
| `0024_detection_shirt_number.sql` | El dorsal escrito para una trayectoria (`detections.player_number`) debe estar entre 0 y 99, igual que en la API (NOT VALID: no revisa filas anteriores) |
| `0025_play_and_formation_rules.sql` | Reglas que ya aplicaba la API, ahora también en la base: tipo de acción de una jugada de hasta 40 caracteres, y formaciones numéricas de 2 a 5 líneas de 1 a 6 jugadores que suman 10 (función `formation_name_is_valid`; NOT VALID) |
| `0026_identification_views.sql` | Vistas de reporte `v_identification_progress` (por clip: trayectorias, con foto, con jugador, solo dorsal, árbitros, externos, pendientes) y `v_action_type_usage` (tipos de acción y cuántas jugadas los usan), con `security_invoker` para que RLS siga aplicando |
| `0027_migration_checksums.sql` | Columna `schema_migrations.checksum`: `scripts/apply_migrations.py` guarda el SHA-256 de cada migración aplicada y se detiene si una ya aplicada fue editada (el fin de línea de Windows no cuenta como cambio) |
| `0028_function_comments.sql` | Descripción de las funciones de RLS y de auditoría, que el diccionario de datos ahora lista junto con las políticas RLS de cada tabla |
| `0029_track_links.sql` | Pares de trayectorias que la IA cree que son el mismo jugador cortado por una oclusión (`track_links`): sus razones (segundos sin verse, distancia, color, equipo), uno a uno, y la decisión de una persona (`SUGGESTED`, `ACCEPTED`, `REJECTED`) con quién y cuándo; RLS por análisis |
| `0030_track_role_suggestions.sql` | Trayectorias con camiseta de ningún equipo agrupadas por color (`track_role_suggestions`): posible árbitro o arquero, con el motivo en palabras; una persona puede descartarlas; RLS por análisis |
| `0031_audit_track_decisions.sql` | La auditoría nombra la fila por sus columnas clave (`análisis/trayectoria`, `row_id` de 80 caracteres) y registra las marcas de árbitro, las decisiones sobre enlaces y las sugerencias descartadas |
| `0032_track_identity_views.sql` | Vistas `v_track_identities` (cada trayectoria de una cadena de enlaces aceptados con la primera de su cadena: el mismo jugador) y `v_track_link_review` (por clip: enlaces por decidir, aceptados, rechazados y sugerencias abiertas), con `security_invoker` |
| `0033_track_number_rules.sql` | El número de trayectoria nunca es negativo en `detections`, `track_snapshots` y `track_labels`, igual que en las tablas nuevas (NOT VALID: no revisa filas anteriores) |

Base nueva: primero `sql/schema.sql` y luego las migraciones.

```bash
pip install psycopg2-binary
DATABASE_URL="postgresql://USER:PASSWORD@HOST/DB?sslmode=require" python scripts/apply_migrations.py
python scripts/apply_migrations.py --list   # ver aplicadas y pendientes
```

### Desde Windows (PowerShell, sin `psql`)

El script solo necesita Python y `psycopg2`, así que sirve en Windows aunque no esté instalado `psql`.
Un comando a la vez:

```powershell
cd C:\ruta\a\TactiSoccerIA-db
git fetch origin
git reset origin/main
git status                      # si muestra archivos borrados (D) o modificados (M), recupéralos:
git restore <archivo> ...       # trae la versión de GitHub de cada uno
$env:DATABASE_URL = Read-Host "URL de Neon"
```

En `Read-Host` lo que va entre comillas es solo la pregunta: presiona Enter y pega la URL cuando
aparezca `URL de Neon:` (nunca la escribas dentro del comando ni la compartas). Luego:

```powershell
python scripts/apply_migrations.py --list   # debe mostrar como PENDING solo las migraciones nuevas
python scripts/apply_migrations.py          # las aplica en orden; termina en "Done."
```

`git reset origin/main` mueve la rama pero no cambia los archivos de la carpeta: por eso hay que
revisar `git status` y recuperar con `git restore` lo que quede viejo antes de aplicar.

Si el script dice `CHANGED` en alguna migración ya aplicada, ese archivo fue editado después de
aplicarse en Neon: no aplica nada hasta que se resuelva. Lo correcto es deshacer la edición y escribir
una migración nueva; `--accept-changes` solo para cambios inofensivos (un comentario).

Si hay migraciones nuevas, aplícalas en Neon **antes** de desplegar el backend que las usa: el backend
nuevo falla si busca tablas o reglas que la base todavía no tiene.

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

Desde la migración 0031 también se auditan `track_labels` (marcas de árbitro o persona externa),
`track_links` (quién aceptó o rechazó cada enlace) y las sugerencias de árbitro o arquero descartadas.
Esas tablas no tienen `id`: la fila se nombra por sus columnas clave, que el trigger recibe como
argumentos (`audit_row_change('analysis_id', 'track_id')`), y queda como `análisis/trayectoria`:

```sql
SELECT changed_at, action, changed_by, changed_fields -> 'status' AS estado FROM audit_log
WHERE table_name = 'track_links' AND row_id LIKE '<id del análisis>/%' ORDER BY changed_at;
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

Antes de subir cambios, `scripts/ci_local.sh` corre en tu PostgreSQL local los mismos pasos que GitHub
Actions (crea y borra dos bases de prueba; nunca lo apuntes a Neon):

```bash
ADMIN_URL=postgresql://postgres:postgres@localhost:5432/postgres bash scripts/ci_local.sh
```

| Archivo | Qué hace | Modifica datos |
|---|---|---|
| `sql/verify_rls.sql` | Demostración de Row-Level Security, también en las fotos de trayectorias, sus marcas, los enlaces y sugerencias de la IA y los tipos de acción | No |
| `sql/checks.sql` | Prueba con `ASSERT` la auditoría, que se rechacen 8 filas inválidas, las vistas y RLS a través de ellas; las fotos de trayectorias, los tipos de acción, las marcas de árbitro/externo y los dorsales 0-99 (migraciones 0021 a 0024); los enlaces entre trayectorias (uno a uno, decisión con fecha), las sugerencias de árbitro o arquero, su auditoría y las cadenas de `v_track_identities` (migraciones 0029 a 0032), con su RLS y su borrado junto al análisis | No (termina en `ROLLBACK`) |
| `sql/verify_data.sql` | Reporte de salud: reglas sin validar, análisis atascados, videos sin análisis, dorsales repetidos, cuentas sin equipo, fotos sin trayectoria, árbitros con jugador asignado, trayectorias identificadas a medias, enlaces aceptados entre trayectorias con dorsales distintos, enlaces cuyos cuadros ya no coinciden con las detecciones, tamaño de cada equipo | No (solo lectura) |

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
