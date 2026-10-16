-- 0008 - Indexes for the queries the app runs most (EXPLAIN before/after in README.md). Idempotent.

-- Review queue and pending reviews: open recommendations of a match.
CREATE INDEX IF NOT EXISTS idx_recommendations_match_status ON ai_recommendations (match_id, status);
-- Analyses waiting or running (startup recovery, admin queue): a small partial index.
CREATE INDEX IF NOT EXISTS idx_analyses_active ON video_analyses (status)
    WHERE status IN ('PENDING', 'PROCESSING');
-- Evolution and comparison read one indicator across analyses.
CREATE INDEX IF NOT EXISTS idx_indicators_analysis_name ON tactical_indicators (video_analysis_id, name);
-- Player ranking counts detections per player.
CREATE INDEX IF NOT EXISTS idx_detections_player ON detections (player_id) WHERE player_id IS NOT NULL;
-- Recommendation -> indicator links, looked up from the indicator side when deleting analyses.
CREATE INDEX IF NOT EXISTS idx_recommendation_indicators_indicator ON recommendation_indicators (indicator_id);
-- Team history of a player and players by shirt number.
CREATE INDEX IF NOT EXISTS idx_player_history_player ON player_team_history (player_id, joined_at);
CREATE INDEX IF NOT EXISTS idx_players_team_shirt ON players (team_id, shirt_number);
-- Latest reports of a team.
CREATE INDEX IF NOT EXISTS idx_reports_team_generated ON reports (team_id, generated_at DESC);
-- Played matches of a team (comparison, evolution, timeline).
CREATE INDEX IF NOT EXISTS idx_matches_team_status_date ON matches (team_id, status, match_date);
