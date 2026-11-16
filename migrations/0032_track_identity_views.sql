-- 0032 - Views over the decisions on cut tracks and kits of no team (same rules as migration 0026).
--
--   v_track_identities    every track that belongs to a chain of ACCEPTED links, with the first track
--                         of its chain (person_track) and its place in it: 12 -> 31 -> 40 gives
--                         (12, 12, 0), (31, 12, 1), (40, 12, 2). Two tracks with the same
--                         person_track are one player, so a shirt number given to one is his in all.
--   v_track_link_review   one row per analysed clip: how many links are waiting for a person,
--                         accepted or rejected, and how many referee / goalkeeper suggestions are
--                         still open (not dismissed and the track not marked yet).
--
-- WITH (security_invoker = true): Row-Level Security still applies through the views. A chain is
-- followed at most MAX_CHAIN steps, so a wrong row can never make the query loop. Idempotent.

CREATE OR REPLACE VIEW v_track_identities WITH (security_invoker = true) AS
WITH RECURSIVE chain AS (
    -- First tracks: they continue nobody (no accepted link ends in them).
    SELECT l.analysis_id, l.from_track AS person_track, l.from_track AS track_id, 0 AS step
    FROM track_links l
    WHERE l.status = 'ACCEPTED'
      AND NOT EXISTS (SELECT 1 FROM track_links before
                      WHERE before.analysis_id = l.analysis_id AND before.to_track = l.from_track
                        AND before.status = 'ACCEPTED')
    UNION ALL
    SELECT c.analysis_id, c.person_track, l.to_track, c.step + 1
    FROM chain c
    JOIN track_links l ON l.analysis_id = c.analysis_id AND l.from_track = c.track_id AND l.status = 'ACCEPTED'
    WHERE c.step < 500  -- MAX_CHAIN
)
SELECT analysis_id, track_id, person_track, step FROM chain;

CREATE OR REPLACE VIEW v_track_link_review WITH (security_invoker = true) AS
SELECT m.team_id,
       m.id AS match_id,
       m.opponent,
       v.id AS video_id,
       v.file_name,
       a.id AS analysis_id,
       a.completed_at,
       (SELECT count(*) FROM track_links l WHERE l.analysis_id = a.id AND l.status = 'SUGGESTED') AS links_pending,
       (SELECT count(*) FROM track_links l WHERE l.analysis_id = a.id AND l.status = 'ACCEPTED') AS links_accepted,
       (SELECT count(*) FROM track_links l WHERE l.analysis_id = a.id AND l.status = 'REJECTED') AS links_rejected,
       (SELECT count(*) FROM track_role_suggestions s WHERE s.analysis_id = a.id) AS role_suggestions,
       (SELECT count(*) FROM track_role_suggestions s
        WHERE s.analysis_id = a.id AND s.dismissed_at IS NULL
          AND NOT EXISTS (SELECT 1 FROM track_labels t WHERE t.analysis_id = s.analysis_id AND t.track_id = s.track_id))
           AS role_suggestions_open,
       (SELECT count(DISTINCT s.kit_group) FROM track_role_suggestions s WHERE s.analysis_id = a.id) AS kits
FROM video_analyses a
JOIN videos v ON v.id = a.video_id
JOIN matches m ON m.id = v.match_id
WHERE a.status = 'COMPLETED' AND a.analysis_mode = 'REAL_VIDEO_ANALYSIS';

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT ON v_track_identities, v_track_link_review TO tactivision_app;
    END IF;
END $$;

COMMENT ON VIEW v_track_identities IS 'Trayectorias unidas por enlaces aceptados: cada una con la primera de su cadena (el mismo jugador).';
COMMENT ON VIEW v_track_link_review IS 'Revisión de cada clip analizado: enlaces por decidir, aceptados y rechazados, y sugerencias de árbitro o arquero abiertas.';
