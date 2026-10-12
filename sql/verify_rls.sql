-- Row-Level Security demo (run in the Neon SQL Editor after migration 0002).
-- Shows that the database itself hides other teams' rows, without any WHERE in the query.
-- Everything runs inside a transaction that is rolled back: no data is changed.

BEGIN;

-- 1) As the database owner (no role switch) every team is visible.
SELECT 'owner' AS who, count(*) AS matches FROM matches;
-- Remember the first team now, while it is still visible.
SELECT set_config('demo.team_id', (SELECT id FROM teams ORDER BY created_at LIMIT 1), true);

-- 2) Act as the application role with NO identity: nothing is visible.
SET LOCAL ROLE tactivision_app;
SELECT 'app, no team' AS who, count(*) AS matches, (SELECT count(*) FROM notifications) AS notifications FROM matches;

-- 3) Identify as the first team: only its rows come back (same queries, no WHERE).
SELECT set_config('app.current_team_id', current_setting('demo.team_id'), true);
SELECT 'app, first team' AS who, count(*) AS matches, (SELECT count(*) FROM notifications) AS notifications FROM matches;

-- 4) Policies installed per table.
SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename;

ROLLBACK;
