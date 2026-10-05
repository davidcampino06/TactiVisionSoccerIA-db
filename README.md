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
