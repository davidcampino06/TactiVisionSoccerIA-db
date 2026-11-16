-- 0023 - A person says what a detected track is when it is not one of the players.
--
--   track_labels   the YOLO model detects "people": it cannot tell a player from the referee, a
--                  linesman or someone outside the game. The staff marks those tracks here
--                  (REFEREE or OTHER); a track without a row is a player. A marked track is left
--                  out of the identification and of the participation ranking.
--
-- The shirt number of a track is not stored here: it goes with its detections
-- (detections.player_number), together with the squad player when one has that number. Idempotent.

CREATE TABLE IF NOT EXISTS track_labels (
    analysis_id VARCHAR(36) NOT NULL REFERENCES video_analyses(id) ON DELETE CASCADE,
    track_id INTEGER NOT NULL,
    role VARCHAR(10) NOT NULL CHECK (role IN ('REFEREE', 'OTHER')),
    labelled_by VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
    labelled_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (analysis_id, track_id)
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON track_labels TO tactivision_app;
    END IF;
END $$;

-- Row-Level Security: visible to whoever can see the analysis (same rule as track_snapshots).
ALTER TABLE track_labels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS track_labels_via_analysis ON track_labels;
CREATE POLICY track_labels_via_analysis ON track_labels FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = track_labels.analysis_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = track_labels.analysis_id));

COMMENT ON TABLE track_labels IS 'Trayectorias que una persona marcó como árbitro o persona externa (no son jugadores).';
COMMENT ON COLUMN track_labels.analysis_id IS 'Análisis al que pertenece; se borra con él.';
COMMENT ON COLUMN track_labels.track_id IS 'Número de la trayectoria dentro del video (el mismo de detections.track_id).';
COMMENT ON COLUMN track_labels.role IS 'REFEREE (árbitro o juez de línea) u OTHER (persona externa al juego).';
COMMENT ON COLUMN track_labels.labelled_by IS 'Quién la marcó.';
COMMENT ON COLUMN track_labels.labelled_at IS 'Cuándo la marcó.';
