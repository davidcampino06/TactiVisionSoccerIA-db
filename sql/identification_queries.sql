-- Who is who in the analysed clips: queries to paste in the Neon SQL Editor or to run with
--     psql "$DATABASE_URL" -f sql/identification_queries.sql
-- They cover every clip; to look at one, write its analysis id in the set_config line below.
-- Nothing is modified: everything is a SELECT and the transaction is rolled back.
--
-- The model (migrations 0021 to 0033): every person the tracker followed is a track. A person says
-- who it is with a squad player or a shirt number (detections), or marks it as referee / outsider
-- (track_labels). The AI helps with a photo of each track (track_snapshots), with tracks that look
-- like the same player cut in two (track_links) and with kits of no team (track_role_suggestions).

BEGIN READ ONLY;

-- '' = every clip; or the id of one analysis, for example 'b3f1...'.
SELECT set_config('identification.analysis', '', true);

-- 1. Review of each clip: what is still waiting for a person.
SELECT p.opponent AS rival, p.file_name AS clip, p.tracks AS trayectorias, p.pending AS sin_identificar,
       r.links_pending AS enlaces_por_decidir, r.links_accepted AS enlaces_aceptados,
       r.role_suggestions_open AS sugerencias_abiertas
FROM v_identification_progress p
JOIN v_track_link_review r ON r.analysis_id = p.analysis_id
WHERE NULLIF(current_setting('identification.analysis'), '') IS NULL OR p.analysis_id = current_setting('identification.analysis')
ORDER BY p.completed_at DESC;

-- 2. Links waiting for a decision, surest first, with the reasons the AI gave.
SELECT analysis_id AS analisis, from_track AS de, to_track AS a, confidence AS confianza,
       gap_seconds AS segundos_sin_verse, distance_heights AS distancia_alturas,
       color_distance AS diferencia_color, same_team AS mismo_equipo
FROM track_links
WHERE status = 'SUGGESTED' AND (NULLIF(current_setting('identification.analysis'), '') IS NULL OR analysis_id = current_setting('identification.analysis'))
ORDER BY analysis_id, confidence DESC;

-- 3. One player in several tracks: the chains of accepted links and the number each track has.
SELECT i.analysis_id AS analisis, i.person_track AS jugador, i.step AS paso, i.track_id AS trayectoria,
       (SELECT max(d.player_number) FROM detections d
        WHERE d.video_analysis_id = i.analysis_id AND d.track_id = i.track_id) AS dorsal
FROM v_track_identities i
WHERE NULLIF(current_setting('identification.analysis'), '') IS NULL OR i.analysis_id = current_setting('identification.analysis')
ORDER BY i.analysis_id, i.person_track, i.step;

-- 4. Kits of no team: who still has to be confirmed (not dismissed, not marked).
SELECT s.analysis_id AS analisis, s.kit_group AS grupo, s.kit_color AS color, s.suggestion AS sugerencia,
       array_agg(s.track_id ORDER BY s.track_id) AS trayectorias,
       count(*) FILTER (WHERE l.track_id IS NOT NULL) AS ya_marcadas
FROM track_role_suggestions s
LEFT JOIN track_labels l ON l.analysis_id = s.analysis_id AND l.track_id = s.track_id
WHERE s.dismissed_at IS NULL AND (NULLIF(current_setting('identification.analysis'), '') IS NULL OR s.analysis_id = current_setting('identification.analysis'))
GROUP BY s.analysis_id, s.kit_group, s.kit_color, s.suggestion
ORDER BY s.analysis_id, s.kit_group;

-- 5. Who decided what (needs the database owner: the application cannot read audit_log).
SELECT changed_at AS cuando, table_name AS tabla, row_id AS fila, action AS accion, changed_by AS quien,
       COALESCE(changed_fields -> 'status' ->> 'new', changed_fields ->> 'role') AS decision
FROM audit_log
WHERE table_name IN ('track_links', 'track_labels', 'track_role_suggestions')
  AND (NULLIF(current_setting('identification.analysis'), '') IS NULL OR row_id LIKE current_setting('identification.analysis') || '/%')
ORDER BY changed_at DESC
LIMIT 50;

ROLLBACK;
