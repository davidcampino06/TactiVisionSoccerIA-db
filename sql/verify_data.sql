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
