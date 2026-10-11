-- 0002 - Row-Level Security: PostgreSQL itself refuses to return another team's rows.
--
-- How it works
--   * tactivision_app is a role WITHOUT the BYPASSRLS privilege. The backend switches to it at the
--     start of every transaction (SET LOCAL ROLE tactivision_app), so these policies always apply.
--   * The backend also stores who is asking, only for that transaction:
--         app.current_user_id, app.current_role, app.current_team_id
--     and app.bypass_rls = 'on' for system work that is not tied to a user (analysis worker,
--     restart recovery, invitation-code lookup).
--   * Tables with team_id compare it with app.current_team_id. Child tables (events, videos,
--     detections...) are visible only if their parent row is visible, so the rule is inherited
--     down the chain: team -> match -> video -> analysis -> detection.
--   * users, formations (shared catalog) and system_status have no RLS.
--
-- This is a second barrier: the API already checks permissions (TeamAccessPolicy). If the API ever
-- had a bug, the database would still not hand over another team's data.
-- Idempotent: it can be run more than once.

-- ------------------------------------------------------------------ role and privileges
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        CREATE ROLE tactivision_app NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
    END IF;
END $$;

-- The connection user (Neon owner / local postgres) must be able to switch to the role.
GRANT tactivision_app TO CURRENT_USER;

GRANT USAGE ON SCHEMA public TO tactivision_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO tactivision_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO tactivision_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tactivision_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO tactivision_app;

-- ------------------------------------------------------------------ request context helpers
CREATE OR REPLACE FUNCTION app_rls_bypass() RETURNS BOOLEAN
    LANGUAGE sql STABLE AS $$ SELECT COALESCE(current_setting('app.bypass_rls', true), '') = 'on' $$;

CREATE OR REPLACE FUNCTION app_current_user() RETURNS VARCHAR
    LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.current_user_id', true), '') $$;

CREATE OR REPLACE FUNCTION app_current_role() RETURNS VARCHAR
    LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.current_role', true), '') $$;

CREATE OR REPLACE FUNCTION app_current_team() RETURNS VARCHAR
    LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.current_team_id', true), '') $$;

CREATE OR REPLACE FUNCTION app_can_see_team(target_team_id VARCHAR) RETURNS BOOLEAN
    LANGUAGE sql STABLE AS $$
        SELECT app_rls_bypass() OR (target_team_id IS NOT NULL AND target_team_id = app_current_team())
    $$;

-- ------------------------------------------------------------------ enable RLS
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_team_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE match_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE match_formations ENABLE ROW LEVEL SECURITY;
ALTER TABLE tactical_plays ENABLE ROW LEVEL SECURITY;
ALTER TABLE tactical_play_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE match_tactical_plays ENABLE ROW LEVEL SECURITY;
ALTER TABLE videos ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_analyses ENABLE ROW LEVEL SECURITY;
ALTER TABLE detections ENABLE ROW LEVEL SECURITY;
ALTER TABLE tactical_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE recommendation_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------ teams
-- Members see and change their team; a coach also sees the team he owns (needed right after
-- creating it); the administrator can only READ team metadata (no tactical tables).
DROP POLICY IF EXISTS teams_member_access ON teams;
CREATE POLICY teams_member_access ON teams FOR ALL
    USING (app_can_see_team(id) OR coach_id = app_current_user())
    WITH CHECK (app_can_see_team(id) OR coach_id = app_current_user());

DROP POLICY IF EXISTS teams_admin_read ON teams;
CREATE POLICY teams_admin_read ON teams FOR SELECT
    USING (app_current_role() = 'ADMINISTRATOR');

-- ------------------------------------------------------------------ tables with team_id
DROP POLICY IF EXISTS players_team_isolation ON players;
CREATE POLICY players_team_isolation ON players FOR ALL
    USING (app_can_see_team(team_id)) WITH CHECK (app_can_see_team(team_id));

DROP POLICY IF EXISTS player_history_team_isolation ON player_team_history;
CREATE POLICY player_history_team_isolation ON player_team_history FOR ALL
    USING (app_can_see_team(team_id)) WITH CHECK (app_can_see_team(team_id));

DROP POLICY IF EXISTS matches_team_isolation ON matches;
CREATE POLICY matches_team_isolation ON matches FOR ALL
    USING (app_can_see_team(team_id)) WITH CHECK (app_can_see_team(team_id));

DROP POLICY IF EXISTS tactical_plays_team_isolation ON tactical_plays;
CREATE POLICY tactical_plays_team_isolation ON tactical_plays FOR ALL
    USING (app_can_see_team(team_id)) WITH CHECK (app_can_see_team(team_id));

DROP POLICY IF EXISTS reports_team_isolation ON reports;
CREATE POLICY reports_team_isolation ON reports FOR ALL
    USING (app_can_see_team(team_id)) WITH CHECK (app_can_see_team(team_id));

-- ------------------------------------------------------------------ children of matches
DROP POLICY IF EXISTS match_events_via_match ON match_events;
CREATE POLICY match_events_via_match ON match_events FOR ALL
    USING (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = match_events.match_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = match_events.match_id));

DROP POLICY IF EXISTS match_formations_via_match ON match_formations;
CREATE POLICY match_formations_via_match ON match_formations FOR ALL
    USING (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = match_formations.match_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = match_formations.match_id));

DROP POLICY IF EXISTS match_tactical_plays_via_match ON match_tactical_plays;
CREATE POLICY match_tactical_plays_via_match ON match_tactical_plays FOR ALL
    USING (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = match_tactical_plays.match_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = match_tactical_plays.match_id));

DROP POLICY IF EXISTS videos_via_match ON videos;
CREATE POLICY videos_via_match ON videos FOR ALL
    USING (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = videos.match_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = videos.match_id));

DROP POLICY IF EXISTS recommendations_via_match ON ai_recommendations;
CREATE POLICY recommendations_via_match ON ai_recommendations FOR ALL
    USING (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = ai_recommendations.match_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (SELECT 1 FROM matches m WHERE m.id = ai_recommendations.match_id));

-- ------------------------------------------------------------------ deeper children
DROP POLICY IF EXISTS play_versions_via_play ON tactical_play_versions;
CREATE POLICY play_versions_via_play ON tactical_play_versions FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM tactical_plays tp WHERE tp.id = tactical_play_versions.tactical_play_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM tactical_plays tp WHERE tp.id = tactical_play_versions.tactical_play_id));

DROP POLICY IF EXISTS analyses_via_video ON video_analyses;
CREATE POLICY analyses_via_video ON video_analyses FOR ALL
    USING (app_rls_bypass() OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_analyses.video_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_analyses.video_id));

DROP POLICY IF EXISTS detections_via_analysis ON detections;
CREATE POLICY detections_via_analysis ON detections FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = detections.video_analysis_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = detections.video_analysis_id));

DROP POLICY IF EXISTS indicators_via_analysis ON tactical_indicators;
CREATE POLICY indicators_via_analysis ON tactical_indicators FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = tactical_indicators.video_analysis_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = tactical_indicators.video_analysis_id));

DROP POLICY IF EXISTS recommendation_links_via_recommendation ON recommendation_indicators;
CREATE POLICY recommendation_links_via_recommendation ON recommendation_indicators FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM ai_recommendations r WHERE r.id = recommendation_indicators.recommendation_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM ai_recommendations r WHERE r.id = recommendation_indicators.recommendation_id));
