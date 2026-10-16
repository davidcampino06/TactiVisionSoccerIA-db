-- 0007 - Extra data rules enforced by the database itself (the API already checks them).
--
--   users                e-mail stored in lower case and shaped like an e-mail; password_hash is a
--                        bcrypt hash (60 characters, "$2a/b/y$"); updated_at not before created_at
--   players              status is one of the app's states
--   player_team_history  a player cannot leave a team before joining it
--   matches              valid status and result; a result needs both scores
--   videos               valid status
--   video_analyses       an analysis cannot end before it starts
--   detections           confidence between 0 and 1
--   ai_recommendations   severity HIGH, MEDIUM or LOW
--   reports, tactical_play_versions   valid type, versions start at 1
--
-- Each rule is added NOT VALID and then validated. If old rows break a rule (data from before),
-- the rule stays NOT VALID: new and updated rows are checked, and a NOTICE names the rule so the old
-- rows can be fixed and validated later. Idempotent.

CREATE OR REPLACE FUNCTION pg_temp.add_rule(table_name text, rule_name text, rule text) RETURNS void
    LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = rule_name) THEN
        EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I CHECK (%s) NOT VALID', table_name, rule_name, rule);
    END IF;
    BEGIN
        EXECUTE format('ALTER TABLE %I VALIDATE CONSTRAINT %I', table_name, rule_name);
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'Rule % on % kept NOT VALID: existing rows break it (new rows are checked).',
            rule_name, table_name;
    END;
END;
$$;

SELECT pg_temp.add_rule('users', 'users_email_lower_case', $r$email = lower(email)$r$);
SELECT pg_temp.add_rule('users', 'users_email_shape', $r$email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'$r$);
SELECT pg_temp.add_rule('users', 'users_password_is_bcrypt',
                        $r$char_length(password_hash) = 60 AND password_hash ~ '^\$2[aby]\$'$r$);
SELECT pg_temp.add_rule('users', 'users_updated_after_created', $r$updated_at >= created_at$r$);

SELECT pg_temp.add_rule('players', 'players_status_valid',
                        $r$status IN ('ACTIVE', 'INJURED', 'SUSPENDED', 'INACTIVE')$r$);
SELECT pg_temp.add_rule('player_team_history', 'history_left_after_joined',
                        $r$left_at IS NULL OR left_at >= joined_at$r$);

SELECT pg_temp.add_rule('matches', 'matches_status_valid', $r$status IN ('SCHEDULED', 'PLAYED', 'CANCELLED')$r$);
SELECT pg_temp.add_rule('matches', 'matches_result_valid', $r$result IS NULL OR result IN ('WIN', 'LOSS', 'DRAW')$r$);
SELECT pg_temp.add_rule('matches', 'matches_result_needs_score',
                        $r$result IS NULL OR (home_score IS NOT NULL AND away_score IS NOT NULL)$r$);

SELECT pg_temp.add_rule('videos', 'videos_status_valid', $r$status IN ('UPLOADED', 'ANALYZING', 'ANALYZED')$r$);
SELECT pg_temp.add_rule('video_analyses', 'analyses_end_after_start',
                        $r$completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at$r$);
SELECT pg_temp.add_rule('detections', 'detections_confidence_range', $r$confidence BETWEEN 0 AND 1$r$);
SELECT pg_temp.add_rule('ai_recommendations', 'recommendations_severity_valid',
                        $r$severity IN ('HIGH', 'MEDIUM', 'LOW')$r$);
SELECT pg_temp.add_rule('reports', 'reports_type_valid',
                        $r$report_type IN ('MATCH', 'VIDEO_ANALYSIS', 'TEAM_EVOLUTION')$r$);
SELECT pg_temp.add_rule('reports', 'reports_version_positive', $r$version >= 1$r$);
SELECT pg_temp.add_rule('tactical_play_versions', 'play_versions_number_positive', $r$version_number >= 1$r$);
