-- 0009 - Views for reports, comparison and evolution.
--
-- They are created WITH (security_invoker = true): the view runs with the permissions of whoever
-- queries it, so Row-Level Security (migration 0002) still applies and a team only sees its rows.
-- Without that option a view runs as its owner and would skip RLS. Idempotent (CREATE OR REPLACE).

-- One row per match: score, videos, analyses and open AI issues.
CREATE OR REPLACE VIEW v_match_summary WITH (security_invoker = true) AS
SELECT m.id AS match_id,
       m.team_id,
       m.opponent,
       m.match_date,
       m.is_home,
       m.status,
       m.result,
       m.home_score,
       m.away_score,
       (SELECT count(*) FROM videos v WHERE v.match_id = m.id) AS videos,
       (SELECT count(*) FROM video_analyses a JOIN videos v ON v.id = a.video_id
         WHERE v.match_id = m.id AND a.status = 'COMPLETED') AS completed_analyses,
       (SELECT count(*) FROM ai_recommendations r
         WHERE r.match_id = m.id AND r.status IN ('GENERATED', 'REVIEWED')) AS open_issues,
       (SELECT count(*) FROM ai_recommendations r
         WHERE r.match_id = m.id AND r.status = 'CONFIRMED') AS confirmed_issues
FROM matches m;

-- Every indicator of every completed analysis, with its match and team (evolution, comparison).
CREATE OR REPLACE VIEW v_analysis_indicators WITH (security_invoker = true) AS
SELECT m.team_id,
       m.id AS match_id,
       m.opponent,
       m.match_date,
       a.id AS analysis_id,
       a.analysis_mode,
       a.completed_at,
       i.name AS indicator,
       i.value,
       i.unit,
       i.threshold
FROM tactical_indicators i
JOIN video_analyses a ON a.id = i.video_analysis_id AND a.status = 'COMPLETED'
JOIN videos v ON v.id = a.video_id
JOIN matches m ON m.id = v.match_id;

-- Participation of each player in the analysed videos (player ranking).
CREATE OR REPLACE VIEW v_player_participation WITH (security_invoker = true) AS
SELECT p.id AS player_id,
       p.team_id,
       p.first_name,
       p.last_name,
       p.shirt_number,
       count(d.id) AS detections,
       count(DISTINCT v.match_id) AS matches,
       count(DISTINCT d.video_analysis_id) AS analyses
FROM players p
LEFT JOIN detections d ON d.player_id = p.id
LEFT JOIN video_analyses a ON a.id = d.video_analysis_id
LEFT JOIN videos v ON v.id = a.video_id
GROUP BY p.id, p.team_id, p.first_name, p.last_name, p.shirt_number;

-- Open possible issues of each team, most severe and most confident first.
CREATE OR REPLACE VIEW v_open_issues WITH (security_invoker = true) AS
SELECT m.team_id,
       r.id AS recommendation_id,
       r.match_id,
       m.opponent,
       m.match_date,
       r.title,
       r.severity,
       r.confidence,
       r.status,
       r.created_at
FROM ai_recommendations r
JOIN matches m ON m.id = r.match_id
WHERE r.status IN ('GENERATED', 'REVIEWED')
ORDER BY CASE r.severity WHEN 'HIGH' THEN 3 WHEN 'MEDIUM' THEN 2 ELSE 1 END DESC,
         r.status = 'GENERATED' DESC, r.confidence DESC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT ON v_match_summary, v_analysis_indicators, v_player_participation, v_open_issues
            TO tactivision_app;
    END IF;
END $$;
