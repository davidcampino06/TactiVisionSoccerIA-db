-- Automatic checks of the database rules (run by GitHub Actions after the migrations).
-- Everything runs inside a transaction that is rolled back: no data is left behind.
-- Any failed ASSERT stops the script with an error.

BEGIN;

-- Sample data: two teams with one match each.
INSERT INTO users (id, first_name, last_name, email, password_hash, role)
VALUES ('chk-coach-a', 'Ana', 'Uno', 'ana@club.com', '$2b$12$' || repeat('a', 53), 'COACH'),
       ('chk-coach-b', 'Beto', 'Dos', 'beto@club.com', '$2b$12$' || repeat('b', 53), 'COACH');
INSERT INTO teams (id, coach_id, name, invitation_code)
VALUES ('chk-team-a', 'chk-coach-a', 'Equipo A', 'CHK-A'), ('chk-team-b', 'chk-coach-b', 'Equipo B', 'CHK-B');
INSERT INTO matches (id, team_id, opponent, match_date, status, result, home_score, away_score)
VALUES ('chk-match-a', 'chk-team-a', 'Rival A', '2026-10-01', 'PLAYED', 'WIN', 2, 1),
       ('chk-match-b', 'chk-team-b', 'Rival B', '2026-10-02', 'SCHEDULED', NULL, NULL, NULL);
INSERT INTO players (id, team_id, first_name, last_name, shirt_number) VALUES ('chk-player', 'chk-team-a', 'Pepe', 'Tres', 9);
INSERT INTO ai_recommendations (id, match_id, title, description, severity, confidence, evidence)
VALUES ('chk-rec-a', 'chk-match-a', 'Posible problema', 'Revisar', 'HIGH', 0.8, 'Evidencia');

-- 1. Audit log: inserts, real updates only, and never the password hash.
DO $$
DECLARE
    fields jsonb;
BEGIN
    ASSERT (SELECT count(*) FROM audit_log WHERE row_id = 'chk-coach-a' AND action = 'INSERT') = 1,
        'the INSERT of a user must be audited';
    ASSERT NOT (SELECT changed_fields FROM audit_log WHERE row_id = 'chk-coach-a' AND action = 'INSERT') ? 'password_hash',
        'the password hash must never be copied to the audit log';

    UPDATE users SET first_name = 'Anita', password_hash = '$2b$12$' || repeat('c', 53) WHERE id = 'chk-coach-a';
    SELECT changed_fields INTO fields FROM audit_log WHERE row_id = 'chk-coach-a' AND action = 'UPDATE';
    ASSERT fields -> 'first_name' ->> 'old' = 'Ana' AND fields -> 'first_name' ->> 'new' = 'Anita',
        'an UPDATE must keep the old and the new value';
    ASSERT fields ->> 'password_hash' = 'changed', 'a password change is noted without its value';
    ASSERT NOT fields::text LIKE '%cccccccc%', 'the new hash must not appear';

    UPDATE users SET first_name = 'Anita' WHERE id = 'chk-coach-a';
    ASSERT (SELECT count(*) FROM audit_log WHERE row_id = 'chk-coach-a' AND action = 'UPDATE') = 1,
        'an UPDATE that changes nothing must not be audited';

    UPDATE ai_recommendations SET status = 'CONFIRMED' WHERE id = 'chk-rec-a';
    ASSERT (SELECT changed_fields -> 'status' ->> 'new' FROM audit_log
            WHERE row_id = 'chk-rec-a' AND action = 'UPDATE') = 'CONFIRMED', 'reviews of AI issues are audited';
    RAISE NOTICE 'OK audit log';
END $$;

-- 2. Data rules: each bad row is rejected.
DO $$
DECLARE
    bad_rows text[] := ARRAY[
        $q$INSERT INTO users (id, first_name, last_name, email, password_hash, role)
           VALUES ('x1', 'X', 'Y', 'Mayus@Club.com', '$2b$12$' || repeat('a', 53), 'COACH')$q$,
        $q$INSERT INTO users (id, first_name, last_name, email, password_hash, role)
           VALUES ('x2', 'X', 'Y', 'no-es-correo', '$2b$12$' || repeat('a', 53), 'COACH')$q$,
        $q$INSERT INTO users (id, first_name, last_name, email, password_hash, role)
           VALUES ('x3', 'X', 'Y', 'plano@club.com', 'Tactica#2026', 'COACH')$q$,
        $q$UPDATE matches SET result = 'WIN', home_score = NULL WHERE id = 'chk-match-b'$q$,
        $q$UPDATE matches SET status = 'POSTPONED' WHERE id = 'chk-match-b'$q$,
        $q$UPDATE ai_recommendations SET severity = 'CRITICAL' WHERE id = 'chk-rec-a'$q$,
        $q$INSERT INTO player_team_history (id, player_id, team_id, joined_at, left_at)
           VALUES ('x4', 'chk-player', 'chk-team-a', '2026-10-10', '2026-10-01')$q$,
        $q$UPDATE players SET status = 'RETIRED' WHERE id = 'chk-player'$q$
    ];
    statement text;
    rejected int := 0;
BEGIN
    FOREACH statement IN ARRAY bad_rows LOOP
        BEGIN
            EXECUTE statement;
            RAISE EXCEPTION 'accepted a row that breaks a rule: %', statement;
        EXCEPTION WHEN check_violation THEN
            rejected := rejected + 1;
        END;
    END LOOP;
    ASSERT rejected = array_length(bad_rows, 1);
    RAISE NOTICE 'OK data rules (% bad rows rejected)', rejected;
END $$;

-- 3. Views: they work, and with security_invoker they keep Row-Level Security.
DO $$
BEGIN
    ASSERT (SELECT completed_analyses FROM v_match_summary WHERE match_id = 'chk-match-a') = 0;
    ASSERT (SELECT count(*) FROM v_open_issues WHERE team_id = 'chk-team-a') = 0, 'a confirmed issue is closed';
    ASSERT (SELECT count(*) FROM v_match_summary WHERE match_id IN ('chk-match-a', 'chk-match-b')) = 2,
        'the database owner sees both teams';
    RAISE NOTICE 'OK views';
END $$;

SET LOCAL ROLE tactivision_app;
SELECT set_config('app.current_user_id', 'chk-coach-a', true),
       set_config('app.current_role', 'COACH', true),
       set_config('app.current_team_id', 'chk-team-a', true);
DO $$
BEGIN
    ASSERT (SELECT array_agg(match_id) FROM v_match_summary
            WHERE match_id IN ('chk-match-a', 'chk-match-b')) = ARRAY['chk-match-a']::varchar[],
        'through the view, team A must only see its own match';
    BEGIN
        PERFORM count(*) FROM audit_log;
        RAISE EXCEPTION 'the application role must not read the audit log';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    RAISE NOTICE 'OK row-level security through views, audit log hidden from the app';
END $$;
RESET ROLE;

ROLLBACK;
