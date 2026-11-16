-- Data health report (read only). Paste it in the Neon SQL Editor or run:
--     psql "$DATABASE_URL" -f sql/verify_data.sql
-- Nothing is modified: every statement is a SELECT and the transaction is rolled back.
-- Each section prints a list that should be EMPTY (or small) on a healthy database.

BEGIN READ ONLY;

-- 1. Rules added as NOT VALID (migration 0007) because old rows broke them.
--    Empty = every rule is enforced on all rows.
SELECT cl.relname AS tabla, con.conname AS regla, pg_get_constraintdef(con.oid) AS definicion
FROM pg_constraint con
JOIN pg_class cl ON cl.oid = con.conrelid
JOIN pg_namespace n ON n.oid = cl.relnamespace
WHERE n.nspname = 'public' AND NOT con.convalidated
ORDER BY 1, 2;

-- 2. How many rows break each NOT VALID rule (to fix them before validating the rule).
DO $$
DECLARE
    rule record;
    broken bigint;
BEGIN
    FOR rule IN
        SELECT cl.relname AS table_name, con.conname, pg_get_constraintdef(con.oid) AS definition
        FROM pg_constraint con
        JOIN pg_class cl ON cl.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = cl.relnamespace
        WHERE n.nspname = 'public' AND NOT con.convalidated AND con.contype = 'c'
    LOOP
        EXECUTE format('SELECT count(*) FROM %I WHERE NOT (%s)', rule.table_name,
                       regexp_replace(rule.definition, '^CHECK \((.*)\)( NOT VALID)?$', '\1'))
        INTO broken;
        RAISE NOTICE '% . %: % filas no cumplen la regla', rule.table_name, rule.conname, broken;
    END LOOP;
END $$;

-- 3. Analyses stuck for more than an hour (the server restarted in the middle).
SELECT a.id, a.status, a.started_at, m.opponent
FROM video_analyses a
JOIN videos v ON v.id = a.video_id
JOIN matches m ON m.id = v.match_id
WHERE a.status IN ('PENDING', 'PROCESSING')
  AND coalesce(a.started_at, v.uploaded_at) < now() - interval '1 hour'
ORDER BY 3;

-- 4. Videos marked ANALYZED without a completed analysis, and the opposite.
SELECT v.id, v.status, v.file_name
FROM videos v
WHERE (v.status = 'ANALYZED') <> EXISTS (
    SELECT 1 FROM video_analyses a WHERE a.video_id = v.id AND a.status = 'COMPLETED');

-- 5. Played matches without a result, and scheduled matches with a score.
SELECT id, opponent, match_date, status, result, home_score, away_score
FROM matches
WHERE (status = 'PLAYED' AND (result IS NULL OR home_score IS NULL OR away_score IS NULL))
   OR (status = 'SCHEDULED' AND (home_score IS NOT NULL OR away_score IS NOT NULL));

-- 6. Two active players of the same team with the same shirt number.
SELECT team_id, shirt_number, string_agg(first_name || ' ' || last_name, ', ') AS jugadores
FROM players
WHERE shirt_number IS NOT NULL AND status = 'ACTIVE'
GROUP BY team_id, shirt_number
HAVING count(*) > 1;

-- 7. Analysts without a team and coaches without a team.
SELECT u.role, u.email, u.created_at
FROM users u
WHERE (u.role = 'ANALYST' AND u.team_id IS NULL)
   OR (u.role = 'COACH' AND NOT EXISTS (SELECT 1 FROM teams t WHERE t.coach_id = u.id))
ORDER BY 1, 3;

-- 8. Recommendations without any supporting indicator (the evidence link is missing).
SELECT r.id, r.title, r.severity
FROM ai_recommendations r
WHERE NOT EXISTS (SELECT 1 FROM recommendation_indicators ri WHERE ri.recommendation_id = r.id);

-- 8b. Track identification (migrations 0021, 0023, 0024). All three lists should be empty.
--     Photos of tracks that have no detections left (a photo nobody can link to a player):
SELECT s.analysis_id AS analisis, s.track_id AS trayectoria
FROM track_snapshots s
WHERE NOT EXISTS (SELECT 1 FROM detections d WHERE d.video_analysis_id = s.analysis_id AND d.track_id = s.track_id)
ORDER BY 1, 2;

--     Tracks marked as referee or outsider that still have a squad player or a shirt number:
SELECT l.analysis_id AS analisis, l.track_id AS trayectoria, l.role AS marca,
       count(*) FILTER (WHERE d.player_id IS NOT NULL OR d.player_number IS NOT NULL) AS detecciones_con_jugador
FROM track_labels l
JOIN detections d ON d.video_analysis_id = l.analysis_id AND d.track_id = l.track_id
GROUP BY 1, 2, 3
HAVING count(*) FILTER (WHERE d.player_id IS NOT NULL OR d.player_number IS NOT NULL) > 0
ORDER BY 1, 2;

--     Tracks whose detections disagree on who the player is (one track = one person: the app
--     writes the player and the number on ALL the detections of the track, never on part of them):
SELECT video_analysis_id AS analisis, track_id AS trayectoria, count(*) AS detecciones,
       count(player_id) AS con_jugador, count(player_number) AS con_dorsal,
       count(DISTINCT player_id) AS jugadores, count(DISTINCT player_number) AS dorsales
FROM detections
WHERE track_id IS NOT NULL
GROUP BY 1, 2
HAVING count(DISTINCT player_id) > 1 OR count(DISTINCT player_number) > 1
    OR count(player_id) NOT IN (0, count(*)) OR count(player_number) NOT IN (0, count(*))
ORDER BY 1, 2;

-- 8c. Suggested links between cut tracks (migration 0029).
--     Accepted links whose two tracks were given different players or shirt numbers: a person said
--     they are one player, so one of the two identifications is wrong.
WITH track_identity AS (
    SELECT video_analysis_id AS analysis_id, track_id, max(player_id) AS player_id, max(player_number) AS player_number
    FROM detections
    WHERE track_id IS NOT NULL
    GROUP BY 1, 2
)
SELECT l.analysis_id AS analisis, l.from_track AS de, l.to_track AS a,
       f.player_id AS jugador_de, t.player_id AS jugador_a, f.player_number AS dorsal_de, t.player_number AS dorsal_a
FROM track_links l
JOIN track_identity f ON f.analysis_id = l.analysis_id AND f.track_id = l.from_track
JOIN track_identity t ON t.analysis_id = l.analysis_id AND t.track_id = l.to_track
WHERE l.status = 'ACCEPTED'
  AND (f.player_id <> t.player_id OR f.player_number <> t.player_number)
ORDER BY 1, 2;

--     Links whose frames no longer match the detections of their tracks (for example a track that
--     has no detections any more): they describe something that is not in the data.
SELECT l.analysis_id AS analisis, l.from_track AS de, l.to_track AS a, l.from_last_frame, f.last_frame,
       l.to_first_frame, t.first_frame
FROM track_links l
LEFT JOIN LATERAL (SELECT max(frame_number) AS last_frame FROM detections d
                   WHERE d.video_analysis_id = l.analysis_id AND d.track_id = l.from_track) f ON true
LEFT JOIN LATERAL (SELECT min(frame_number) AS first_frame FROM detections d
                   WHERE d.video_analysis_id = l.analysis_id AND d.track_id = l.to_track) t ON true
WHERE f.last_frame IS DISTINCT FROM l.from_last_frame OR t.first_frame IS DISTINCT FROM l.to_first_frame
ORDER BY 1, 2;

-- 9. Size of each team: the general picture (not an error list).
SELECT t.name AS equipo,
       (SELECT count(*) FROM players p WHERE p.team_id = t.id) AS jugadores,
       (SELECT count(*) FROM users u WHERE u.team_id = t.id) AS analistas,
       (SELECT count(*) FROM matches m WHERE m.team_id = t.id) AS partidos,
       (SELECT count(*) FROM videos v JOIN matches m ON m.id = v.match_id WHERE m.team_id = t.id) AS videos,
       (SELECT count(*) FROM video_analyses a JOIN videos v ON v.id = a.video_id
          JOIN matches m ON m.id = v.match_id WHERE m.team_id = t.id AND a.status = 'COMPLETED') AS analisis,
       (SELECT count(*) FROM ai_recommendations r JOIN matches m ON m.id = r.match_id WHERE m.team_id = t.id) AS recomendaciones
FROM teams t
ORDER BY t.name;

-- 10. Rows per table (live estimate from the statistics, no full scan).
SELECT relname AS tabla, n_live_tup AS filas
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY relname;

ROLLBACK;
