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

-- 3b) The same isolation covers the newer tables: clips' track photos and labels (through their
--     analysis) and the team's own action types. Before choosing a team they all count 0.
SELECT 'app, first team' AS who,
       (SELECT count(*) FROM track_snapshots) AS track_photos,
       (SELECT count(*) FROM track_labels) AS track_labels,
       (SELECT count(*) FROM team_action_types) AS action_types,
       (SELECT count(*) FROM v_identification_progress) AS identified_clips;
SELECT set_config('app.current_team_id', 'no-such-team', true);
SELECT 'app, unknown team' AS who,
       (SELECT count(*) FROM track_snapshots) AS track_photos,
       (SELECT count(*) FROM team_action_types) AS action_types;

-- 4) Policies installed per table.
SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename;

ROLLBACK;
