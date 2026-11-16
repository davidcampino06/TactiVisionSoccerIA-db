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

-- 4. Track photos (migration 0021): one small JPEG per track; shirt numbers 0 to 99 (migration 0024).
INSERT INTO videos (id, match_id, file_name, file_path, format, file_size)
VALUES ('chk-video-a', 'chk-match-a', 'clip.mp4', 'uploads/clip.mp4', 'MP4', 1000);
INSERT INTO video_analyses (id, video_id, status) VALUES ('chk-analysis-a', 'chk-video-a', 'COMPLETED');
INSERT INTO detections (id, video_analysis_id, frame_number, timestamp, object_type, confidence,
                        bounding_box_x, bounding_box_y, bounding_box_width, bounding_box_height, track_id)
VALUES ('chk-det-a', 'chk-analysis-a', 0, 0, 'PLAYER', 0.9, 10, 10, 20, 40, 1);
DO $$
DECLARE
    bad_rows text[] := ARRAY[
        $q$INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image)
           VALUES ('chk-analysis-a', 2, 0, 0, 0.9, 20, 40, ''::bytea)$q$,
        $q$INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image)
           VALUES ('chk-analysis-a', 3, 0, 0, 0.9, 20, 40, convert_to(repeat('x', 60001), 'UTF8'))$q$,
        $q$INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image)
           VALUES ('chk-analysis-a', 4, 0, 0, 1.5, 20, 40, '\xffd8ff'::bytea)$q$,
        $q$INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image)
           VALUES ('chk-analysis-a', 5, -1, 0, 0.9, 20, 40, '\xffd8ff'::bytea)$q$,
        $q$INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image)
           VALUES ('chk-analysis-a', 6, 0, 0, 0.9, 20, 0, '\xffd8ff'::bytea)$q$,
        $q$UPDATE detections SET player_number = 100 WHERE id = 'chk-det-a'$q$,
        $q$UPDATE detections SET player_number = -1 WHERE id = 'chk-det-a'$q$
    ];
    statement text;
    rejected int := 0;
BEGIN
    FOREACH statement IN ARRAY bad_rows LOOP
        BEGIN
            EXECUTE statement;
            RAISE EXCEPTION 'accepted a track row that breaks a rule: %', statement;
        EXCEPTION WHEN check_violation THEN
            rejected := rejected + 1;
        END;
    END LOOP;
    ASSERT rejected = array_length(bad_rows, 1);

    INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image)
    VALUES ('chk-analysis-a', 1, 0, 0, 0.9, 20, 40, '\xffd8ff'::bytea);
    BEGIN
        INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image)
        VALUES ('chk-analysis-a', 1, 5, 0.2, 0.8, 20, 40, '\xffd8ff'::bytea);
        RAISE EXCEPTION 'a track must have one photo only';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;
    RAISE NOTICE 'OK track photos (% bad rows rejected, one photo per track)', rejected;
END $$;

-- 5. Action types written by a team and the limits of a play's texts (migration 0022).
INSERT INTO team_action_types (id, team_id, name) VALUES ('chk-type-a', 'chk-team-a', 'Saque de banda largo');
DO $$
DECLARE
    bad_rows text[] := ARRAY[
        $q$INSERT INTO team_action_types (id, team_id, name) VALUES ('x5', 'chk-team-a', 'x')$q$,
        $q$INSERT INTO team_action_types (id, team_id, name) VALUES ('x6', 'chk-team-a', ' Con espacios ')$q$,
        $q$INSERT INTO tactical_plays (id, team_id, name) VALUES ('x7', 'chk-team-a', repeat('n', 51))$q$,
        $q$INSERT INTO tactical_plays (id, team_id, name, description) VALUES ('x8', 'chk-team-a', 'Jugada', repeat('d', 101))$q$
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

    -- One name per team whatever the case; another team may use the same name.
    BEGIN
        INSERT INTO team_action_types (id, team_id, name) VALUES ('x9', 'chk-team-a', 'SAQUE DE BANDA LARGO');
        RAISE EXCEPTION 'the same action type must not be saved twice in a team';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;
    INSERT INTO team_action_types (id, team_id, name) VALUES ('chk-type-b', 'chk-team-b', 'Saque de banda largo');

    -- The limits are exactly 50 and 100 characters.
    INSERT INTO tactical_plays (id, team_id, name, description)
    VALUES ('chk-play-a', 'chk-team-a', repeat('n', 50), repeat('d', 100));
    RAISE NOTICE 'OK action types and play texts (% bad rows rejected, unique per team)', rejected;
END $$;

-- 6. Tracks marked as referee or outsider (migration 0023), and the privacy of the new tables.
DO $$
BEGIN
    BEGIN
        INSERT INTO track_labels (analysis_id, track_id, role) VALUES ('chk-analysis-a', 1, 'COACH');
        RAISE EXCEPTION 'a track can only be marked as REFEREE or OTHER';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
    INSERT INTO track_labels (analysis_id, track_id, role) VALUES ('chk-analysis-a', 1, 'REFEREE');
    RAISE NOTICE 'OK track labels';
END $$;

SET LOCAL ROLE tactivision_app;
SELECT set_config('app.current_user_id', 'chk-coach-b', true),
       set_config('app.current_role', 'COACH', true),
       set_config('app.current_team_id', 'chk-team-b', true);
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM track_snapshots) = 0, 'team B must not see the track photos of team A';
    ASSERT (SELECT count(*) FROM track_labels) = 0, 'team B must not see the track labels of team A';
    ASSERT (SELECT array_agg(id) FROM team_action_types) = ARRAY['chk-type-b']::varchar[],
        'team B must only see its own action types';
    BEGIN
        INSERT INTO track_labels (analysis_id, track_id, role) VALUES ('chk-analysis-a', 9, 'OTHER');
        RAISE EXCEPTION 'team B must not mark tracks of team A';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    RAISE NOTICE 'OK row-level security of track photos, track labels and action types';
END $$;
RESET ROLE;

-- Deleting the analysis takes its photos and labels with it.
DO $$
BEGIN
    DELETE FROM video_analyses WHERE id = 'chk-analysis-a';
    ASSERT (SELECT count(*) FROM track_snapshots WHERE analysis_id = 'chk-analysis-a') = 0, 'photos must go with the analysis';
    ASSERT (SELECT count(*) FROM track_labels WHERE analysis_id = 'chk-analysis-a') = 0, 'labels must go with the analysis';
    RAISE NOTICE 'OK photos and labels are deleted with their analysis';
END $$;

-- 7. Action type length and custom formations (migration 0025).
DO $$
DECLARE
    bad_rows text[] := ARRAY[
        $q$INSERT INTO tactical_plays (id, team_id, name, action_type) VALUES ('x10', 'chk-team-a', 'Jugada', repeat('t', 41))$q$,
        $q$INSERT INTO formations (id, name) VALUES ('x11', '4-4-3')$q$,
        $q$INSERT INTO formations (id, name) VALUES ('x12', '7-2-1')$q$,
        $q$INSERT INTO formations (id, name) VALUES ('x13', '1-1-1-1-1-5')$q$,
        $q$INSERT INTO formations (id, name) VALUES ('x14', '10')$q$
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
    -- A valid custom system, and a name that is not a system, are accepted.
    INSERT INTO formations (id, name) VALUES ('chk-form-1', '3-4-2-1'), ('chk-form-2', '4-1-2-1-2'), ('chk-form-3', 'Rombo');
    INSERT INTO tactical_plays (id, team_id, name, action_type) VALUES ('chk-play-b', 'chk-team-a', 'Jugada', repeat('t', 40));
    RAISE NOTICE 'OK action type length and custom formations (% bad rows rejected)', rejected;
END $$;

-- 8. Report views of the identification and of the action types (migration 0026).
INSERT INTO video_analyses (id, video_id, status) VALUES ('chk-analysis-b', 'chk-video-a', 'COMPLETED');
INSERT INTO detections (id, video_analysis_id, frame_number, timestamp, object_type, confidence, bounding_box_x,
                        bounding_box_y, bounding_box_width, bounding_box_height, track_id, player_id, player_number)
VALUES ('chk-d1', 'chk-analysis-b', 0, 0, 'PLAYER', 0.9, 1, 1, 20, 40, 1, 'chk-player', 9),   -- a squad player
       ('chk-d2', 'chk-analysis-b', 1, 0.1, 'PLAYER', 0.9, 1, 1, 20, 40, 1, 'chk-player', 9),
       ('chk-d3', 'chk-analysis-b', 0, 0, 'PLAYER', 0.9, 50, 1, 20, 40, 2, NULL, 23),         -- only a number
       ('chk-d4', 'chk-analysis-b', 0, 0, 'PLAYER', 0.9, 90, 1, 20, 40, 3, NULL, NULL),       -- the referee
       ('chk-d5', 'chk-analysis-b', 0, 0, 'PLAYER', 0.9, 130, 1, 20, 40, 4, NULL, NULL),      -- nobody yet
       ('chk-d6', 'chk-analysis-b', 0, 0, 'BALL', 0.5, 10, 10, 4, 4, NULL, NULL, NULL);       -- not a track
INSERT INTO track_labels (analysis_id, track_id, role) VALUES ('chk-analysis-b', 3, 'REFEREE');
INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image)
VALUES ('chk-analysis-b', 1, 0, 0, 0.9, 20, 40, '\xffd8ff'::bytea), ('chk-analysis-b', 2, 0, 0, 0.9, 20, 40, '\xffd8ff'::bytea);
DO $$
DECLARE
    row record;
BEGIN
    SELECT * INTO row FROM v_identification_progress WHERE analysis_id = 'chk-analysis-b';
    ASSERT (row.tracks, row.tracks_with_photo, row.with_player, row.number_only, row.referees, row.outsiders, row.pending)
         = (4::bigint, 2::bigint, 1::bigint, 1::bigint, 1::bigint, 0::bigint, 1::bigint),
        format('identification progress is wrong: %s', row);
    ASSERT (SELECT plays FROM v_action_type_usage WHERE action_type_id = 'chk-type-a') = 0,
        'no play of team A uses its action type yet';
    UPDATE tactical_plays SET action_type = 'Saque de banda largo' WHERE id = 'chk-play-b';
    ASSERT (SELECT plays FROM v_action_type_usage WHERE action_type_id = 'chk-type-a') = 1,
        'the play that uses the type must be counted';
    RAISE NOTICE 'OK identification progress and action type usage';
END $$;

SET LOCAL ROLE tactivision_app;
SELECT set_config('app.current_user_id', 'chk-coach-b', true),
       set_config('app.current_role', 'COACH', true),
       set_config('app.current_team_id', 'chk-team-b', true);
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM v_identification_progress) = 0, 'team B must not see the clips of team A';
    ASSERT (SELECT array_agg(action_type_id) FROM v_action_type_usage) = ARRAY['chk-type-b']::varchar[],
        'team B must only see its own action types through the view';
    RAISE NOTICE 'OK row-level security through the identification views';
END $$;
RESET ROLE;

-- 9. Suggested links between cut tracks (migration 0029).
DO $$
DECLARE
    bad_rows text[] := ARRAY[
        $q$INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence) VALUES ('chk-analysis-b', 5, 5, 10, 20, 0.4, 0.1, 0.9)$q$,
        $q$INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence) VALUES ('chk-analysis-b', 5, 6, 20, 20, 0.4, 0.1, 0.9)$q$,
        $q$INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence) VALUES ('chk-analysis-b', 5, 6, 10, 20, 0, 0.1, 0.9)$q$,
        $q$INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence) VALUES ('chk-analysis-b', 5, 6, 10, 20, 0.4, 0.1, 1.2)$q$,
        $q$INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence, status) VALUES ('chk-analysis-b', 5, 6, 10, 20, 0.4, 0.1, 0.9, 'MAYBE')$q$,
        $q$INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence, status) VALUES ('chk-analysis-b', 5, 6, 10, 20, 0.4, 0.1, 0.9, 'ACCEPTED')$q$,
        $q$INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence, decided_at) VALUES ('chk-analysis-b', 5, 6, 10, 20, 0.4, 0.1, 0.9, now())$q$
    ];
    statement text;
    rejected int := 0;
BEGIN
    FOREACH statement IN ARRAY bad_rows LOOP
        BEGIN
            EXECUTE statement;
            RAISE EXCEPTION 'accepted a link that breaks a rule: %', statement;
        EXCEPTION WHEN check_violation THEN
            rejected := rejected + 1;
        END;
    END LOOP;
    ASSERT rejected = array_length(bad_rows, 1);

    -- One-to-one: a track continues one track and is continued by one.
    INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds,
                             distance_heights, color_distance, same_team, confidence)
    VALUES ('chk-analysis-b', 1, 2, 10, 18, 0.32, 0.12, 4.28, true, 0.9),
           ('chk-analysis-b', 2, 4, 30, 40, 0.4, 0.3, NULL, NULL, 0.7);
    BEGIN
        INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence)
        VALUES ('chk-analysis-b', 3, 2, 5, 18, 0.5, 0.2, 0.6);
        RAISE EXCEPTION 'track 2 must not continue two tracks';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;
    UPDATE track_links SET status = 'ACCEPTED', decided_at = now(), decided_by = 'chk-coach-a'
    WHERE analysis_id = 'chk-analysis-b' AND from_track = 1;
    RAISE NOTICE 'OK track links (% bad rows rejected, one-to-one, decision with its date)', rejected;
END $$;

-- 10. Referee and goalkeeper suggestions grouped by kit (migration 0030).
DO $$
DECLARE
    bad_rows text[] := ARRAY[
        $q$INSERT INTO track_role_suggestions (analysis_id, track_id, suggestion, kit_group, kit_color, kit_tracks, confidence, reason) VALUES ('chk-analysis-b', 7, 'COACH', 1, '#3bb3c2', 1, 0.5, 'x')$q$,
        $q$INSERT INTO track_role_suggestions (analysis_id, track_id, suggestion, kit_group, kit_color, kit_tracks, confidence, reason) VALUES ('chk-analysis-b', 7, 'REFEREE', 0, '#3bb3c2', 1, 0.5, 'x')$q$,
        $q$INSERT INTO track_role_suggestions (analysis_id, track_id, suggestion, kit_group, kit_color, kit_tracks, confidence, reason) VALUES ('chk-analysis-b', 7, 'REFEREE', 1, 'cyan', 1, 0.5, 'x')$q$,
        $q$INSERT INTO track_role_suggestions (analysis_id, track_id, suggestion, kit_group, kit_color, kit_tracks, confidence, reason) VALUES ('chk-analysis-b', 7, 'REFEREE', 1, '#3BB3C2', 1, 0.5, 'x')$q$,
        $q$INSERT INTO track_role_suggestions (analysis_id, track_id, suggestion, kit_group, kit_color, kit_tracks, confidence, reason) VALUES ('chk-analysis-b', 7, 'REFEREE', 1, '#3bb3c2', 1, 0.5, '   ')$q$,
        $q$INSERT INTO track_role_suggestions (analysis_id, track_id, suggestion, kit_group, kit_color, kit_tracks, confidence, reason, dismissed_by) VALUES ('chk-analysis-b', 7, 'REFEREE', 1, '#3bb3c2', 1, 0.5, 'x', 'chk-coach-a')$q$
    ];
    statement text;
    rejected int := 0;
BEGIN
    FOREACH statement IN ARRAY bad_rows LOOP
        BEGIN
            EXECUTE statement;
            RAISE EXCEPTION 'accepted a suggestion that breaks a rule: %', statement;
        EXCEPTION WHEN check_violation THEN
            rejected := rejected + 1;
        END;
    END LOOP;
    ASSERT rejected = array_length(bad_rows, 1);
    -- The referee (two tracks of the same kit) and somebody on the touchline (one track).
    INSERT INTO track_role_suggestions (analysis_id, track_id, suggestion, kit_group, kit_color, kit_tracks, confidence, reason)
    VALUES ('chk-analysis-b', 3, 'GOALKEEPER_OR_REFEREE', 1, '#3bb3c2', 2, 0.5, 'Camiseta #3bb3c2, de ningún equipo'),
           ('chk-analysis-b', 5, 'GOALKEEPER_OR_REFEREE', 1, '#3bb3c2', 2, 0.5, 'Camiseta #3bb3c2, de ningún equipo'),
           ('chk-analysis-b', 6, 'GOALKEEPER_OR_REFEREE', 2, '#23323f', 1, 0.5, 'Camiseta #23323f, de ningún equipo');
    UPDATE track_role_suggestions SET dismissed_at = now(), dismissed_by = 'chk-coach-a'
    WHERE analysis_id = 'chk-analysis-b' AND track_id = 6;
    RAISE NOTICE 'OK role suggestions (% bad rows rejected)', rejected;
END $$;

-- 11. Audit of the track decisions, named by analysis/track (migration 0031).
DO $$
DECLARE
    fields jsonb;
BEGIN
    ASSERT (SELECT count(*) FROM audit_log WHERE table_name = 'track_labels' AND row_id = 'chk-analysis-b/3'
            AND action = 'INSERT') = 1, 'marking the referee must be audited with analysis/track';
    SELECT changed_fields INTO fields FROM audit_log
    WHERE table_name = 'track_links' AND row_id = 'chk-analysis-b/1' AND action = 'UPDATE';
    ASSERT fields -> 'status' ->> 'old' = 'SUGGESTED' AND fields -> 'status' ->> 'new' = 'ACCEPTED',
        format('accepting a link must be audited: %s', fields);
    ASSERT fields -> 'decided_by' ->> 'new' = 'chk-coach-a', 'and who accepted it';
    -- The suggestions written by the analysis are not audited; dismissing one is.
    ASSERT (SELECT count(*) FROM audit_log WHERE table_name = 'track_role_suggestions') = 1,
        'only the dismissed suggestion must be audited';
    ASSERT (SELECT row_id FROM audit_log WHERE table_name = 'track_role_suggestions') = 'chk-analysis-b/6';
    -- Tables with an id are still named by it.
    ASSERT (SELECT count(*) FROM audit_log WHERE table_name = 'users' AND row_id = 'chk-coach-a') >= 1;
    RAISE NOTICE 'OK audit of track labels, link decisions and dismissed suggestions';
END $$;

-- 12. Views of linked tracks and of the review (migration 0032), privacy and deletion of the new tables.
DO $$
DECLARE
    row record;
BEGIN
    SELECT * INTO row FROM v_track_link_review WHERE analysis_id = 'chk-analysis-b';
    ASSERT (row.links_pending, row.links_accepted, row.links_rejected, row.role_suggestions,
            row.role_suggestions_open, row.kits) = (1::bigint, 1::bigint, 0::bigint, 3::bigint, 1::bigint, 2::bigint),
        format('the review of the clip is wrong: %s', row);
    ASSERT (SELECT array_agg(ARRAY[track_id, person_track, step] ORDER BY step) FROM v_track_identities
            WHERE analysis_id = 'chk-analysis-b') = ARRAY[ARRAY[1, 1, 0], ARRAY[2, 1, 1]],
        'only the accepted link makes a chain';
    UPDATE track_links SET status = 'ACCEPTED', decided_at = now() WHERE analysis_id = 'chk-analysis-b' AND from_track = 2;
    ASSERT (SELECT array_agg(ARRAY[track_id, person_track, step] ORDER BY step) FROM v_track_identities
            WHERE analysis_id = 'chk-analysis-b') = ARRAY[ARRAY[1, 1, 0], ARRAY[2, 1, 1], ARRAY[4, 1, 2]],
        'tracks 1, 2 and 4 must be one player';
    UPDATE track_links SET status = 'REJECTED' WHERE analysis_id = 'chk-analysis-b' AND from_track = 1;
    ASSERT (SELECT array_agg(ARRAY[track_id, person_track] ORDER BY step) FROM v_track_identities
            WHERE analysis_id = 'chk-analysis-b') = ARRAY[ARRAY[2, 2], ARRAY[4, 2]],
        'a rejected link cuts the chain';
    RAISE NOTICE 'OK linked tracks and the review of each clip';
END $$;

SET LOCAL ROLE tactivision_app;
SELECT set_config('app.current_user_id', 'chk-coach-b', true),
       set_config('app.current_role', 'COACH', true),
       set_config('app.current_team_id', 'chk-team-b', true);
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM track_links) = 0, 'team B must not see the links of team A';
    ASSERT (SELECT count(*) FROM track_role_suggestions) = 0, 'team B must not see the suggestions of team A';
    ASSERT (SELECT count(*) FROM v_track_identities) = 0, 'nor the chains through the view';
    ASSERT (SELECT count(*) FROM v_track_link_review) = 0, 'nor the review of the clips of team A';
    BEGIN
        UPDATE track_links SET status = 'REJECTED', decided_at = now() WHERE analysis_id = 'chk-analysis-b';
        ASSERT NOT FOUND, 'team B must not decide on the links of team A';
        INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence)
        VALUES ('chk-analysis-b', 9, 10, 1, 5, 0.2, 0.1, 0.8);
        RAISE EXCEPTION 'team B must not add links to an analysis of team A';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    RAISE NOTICE 'OK row-level security of track links, role suggestions and their views';
END $$;
RESET ROLE;

DO $$
BEGIN
    DELETE FROM video_analyses WHERE id = 'chk-analysis-b';
    ASSERT (SELECT count(*) FROM track_links WHERE analysis_id = 'chk-analysis-b') = 0, 'links must go with the analysis';
    ASSERT (SELECT count(*) FROM track_role_suggestions WHERE analysis_id = 'chk-analysis-b') = 0,
        'suggestions must go with the analysis';
    RAISE NOTICE 'OK links and role suggestions are deleted with their analysis';
END $$;

-- 13. A track number is never negative (migration 0033), in every table that names a track.
DO $$
DECLARE
    bad_rows text[] := ARRAY[
        $q$INSERT INTO detections (id, video_analysis_id, frame_number, timestamp, object_type, confidence, bounding_box_x, bounding_box_y, bounding_box_width, bounding_box_height, track_id) VALUES ('chk-neg', 'chk-analysis-c', 0, 0, 'PLAYER', 0.9, 1, 1, 20, 40, -1)$q$,
        $q$INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image) VALUES ('chk-analysis-c', -1, 0, 0, 0.9, 20, 40, '\xffd8ff'::bytea)$q$,
        $q$INSERT INTO track_labels (analysis_id, track_id, role) VALUES ('chk-analysis-c', -1, 'OTHER')$q$,
        $q$INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds, distance_heights, confidence) VALUES ('chk-analysis-c', -1, 2, 1, 5, 0.2, 0.1, 0.8)$q$,
        $q$INSERT INTO track_role_suggestions (analysis_id, track_id, suggestion, kit_group, kit_color, kit_tracks, confidence, reason) VALUES ('chk-analysis-c', -1, 'REFEREE', 1, '#3bb3c2', 1, 0.5, 'x')$q$
    ];
    statement text;
    rejected int := 0;
BEGIN
    INSERT INTO video_analyses (id, video_id, status) VALUES ('chk-analysis-c', 'chk-video-a', 'COMPLETED');
    FOREACH statement IN ARRAY bad_rows LOOP
        BEGIN
            EXECUTE statement;
            RAISE EXCEPTION 'accepted a negative track number: %', statement;
        EXCEPTION WHEN check_violation THEN
            rejected := rejected + 1;
        END;
    END LOOP;
    ASSERT rejected = array_length(bad_rows, 1);
    -- A detection the tracker did not follow has no number, and that is fine.
    INSERT INTO detections (id, video_analysis_id, frame_number, timestamp, object_type, confidence, bounding_box_x,
                            bounding_box_y, bounding_box_width, bounding_box_height, track_id)
    VALUES ('chk-untracked', 'chk-analysis-c', 0, 0, 'PLAYER', 0.6, 1, 1, 20, 40, NULL);
    RAISE NOTICE 'OK track numbers (% negative ones rejected in 5 tables)', rejected;
END $$;

-- 14. A loop of accepted links (1 -> 2 -> 1, each row valid by itself) never hangs v_track_identities:
--     a loop has no first track, so it gives no chain (sql/verify_data.sql lists it for a person).
DO $$
BEGIN
    INSERT INTO video_analyses (id, video_id, status) VALUES ('chk-analysis-d', 'chk-video-a', 'COMPLETED');
    INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds,
                             distance_heights, confidence, status, decided_at)
    VALUES ('chk-analysis-d', 1, 2, 10, 20, 0.4, 0.1, 0.9, 'ACCEPTED', now()),
           ('chk-analysis-d', 2, 1, 30, 40, 0.4, 0.1, 0.9, 'ACCEPTED', now()),
           ('chk-analysis-d', 5, 6, 10, 20, 0.4, 0.1, 0.9, 'ACCEPTED', now());
    SET LOCAL statement_timeout = '5s';
    ASSERT (SELECT array_agg(track_id ORDER BY track_id) FROM v_track_identities WHERE analysis_id = 'chk-analysis-d')
         = ARRAY[5, 6], 'the loop must give no chain and the other link must still give its own';
    RESET statement_timeout;
    RAISE NOTICE 'OK a loop of links gives no chain and does not hang the view';
END $$;

ROLLBACK;
