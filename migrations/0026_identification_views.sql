-- 0026 - Report views of the new features (same rules as migration 0009).
--
--   v_identification_progress   one row per analysed clip: how many tracks the AI followed, how many
--                               have a photo, and how many a person already identified (a squad
--                               player, only a shirt number, the referee or someone outside). It is
--                               the "X de Y trayectorias identificadas" of the app, for every clip.
--   v_action_type_usage         each action type a team wrote and how many of its plays use it.
--
-- WITH (security_invoker = true): they run with the permissions of whoever queries them, so
-- Row-Level Security still applies and a team only sees its own rows. Idempotent.

CREATE OR REPLACE VIEW v_identification_progress WITH (security_invoker = true) AS
WITH tracks AS (
    SELECT d.video_analysis_id AS analysis_id,
           d.track_id,
           bool_or(d.player_id IS NOT NULL) AS has_player,
           bool_or(d.player_number IS NOT NULL) AS has_number
    FROM detections d
    WHERE d.track_id IS NOT NULL
    GROUP BY d.video_analysis_id, d.track_id
)
SELECT m.team_id,
       m.id AS match_id,
       m.opponent,
       v.id AS video_id,
       v.file_name,
       a.id AS analysis_id,
       a.completed_at,
       count(t.track_id) AS tracks,
       count(s.track_id) AS tracks_with_photo,
       count(t.track_id) FILTER (WHERE t.has_player) AS with_player,
       count(t.track_id) FILTER (WHERE NOT t.has_player AND t.has_number) AS number_only,
       count(t.track_id) FILTER (WHERE l.role = 'REFEREE') AS referees,
       count(t.track_id) FILTER (WHERE l.role = 'OTHER') AS outsiders,
       count(t.track_id) FILTER (WHERE NOT t.has_player AND NOT t.has_number AND l.role IS NULL) AS pending
FROM video_analyses a
JOIN videos v ON v.id = a.video_id
JOIN matches m ON m.id = v.match_id
LEFT JOIN tracks t ON t.analysis_id = a.id
LEFT JOIN track_snapshots s ON s.analysis_id = t.analysis_id AND s.track_id = t.track_id
LEFT JOIN track_labels l ON l.analysis_id = t.analysis_id AND l.track_id = t.track_id
WHERE a.status = 'COMPLETED' AND a.analysis_mode = 'REAL_VIDEO_ANALYSIS'
GROUP BY m.team_id, m.id, m.opponent, v.id, v.file_name, a.id, a.completed_at;

CREATE OR REPLACE VIEW v_action_type_usage WITH (security_invoker = true) AS
SELECT k.team_id,
       k.id AS action_type_id,
       k.name,
       k.created_at,
       (SELECT count(*) FROM tactical_plays p WHERE p.team_id = k.team_id AND p.action_type = k.name) AS plays
FROM team_action_types k;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT ON v_identification_progress, v_action_type_usage TO tactivision_app;
    END IF;
END $$;

COMMENT ON VIEW v_identification_progress IS 'Avance de la identificación de cada clip analizado: trayectorias, con foto, con jugador, solo con dorsal, árbitros, externos y pendientes.';
COMMENT ON VIEW v_action_type_usage IS 'Tipos de acción escritos por cada equipo y cuántas de sus jugadas los usan.';
