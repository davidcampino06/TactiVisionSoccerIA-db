-- 0021 - One photo per detected track, so the staff can tell who is who.
--
--   track_snapshots   the best crop of each track of an analysis (the AI repo, track_crops.py): the
--                     clearest view of that player in the video itself, as a small JPEG, with the
--                     frame and second it was taken from.
--
-- A track id is only a number inside one video. Linking it to a squad player is manual (no face
-- recognition, no biometrics): the staff looks at the photo, recognises the shirt or the number and
-- picks the player. The photo comes from the video the team uploaded; it belongs to the analysis
-- and is deleted with it. Analyses stored before this migration have no photos. Idempotent.

CREATE TABLE IF NOT EXISTS track_snapshots (
    analysis_id VARCHAR(36) NOT NULL REFERENCES video_analyses(id) ON DELETE CASCADE,
    track_id INTEGER NOT NULL,
    frame_number INTEGER NOT NULL CHECK (frame_number >= 0),
    timestamp DECIMAL(10, 4) NOT NULL CHECK (timestamp >= 0),
    confidence DECIMAL(10, 4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    width INTEGER NOT NULL CHECK (width > 0),
    height INTEGER NOT NULL CHECK (height > 0),
    image BYTEA NOT NULL CHECK (octet_length(image) BETWEEN 1 AND 60000),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (analysis_id, track_id)
);

DO $$
BEGIN
    -- The application role needs the same privileges as on the other tables (migration 0002).
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON track_snapshots TO tactivision_app;
    END IF;
END $$;

-- Row-Level Security: visible to whoever can see the analysis (same rule as analysis_strengths).
ALTER TABLE track_snapshots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS track_snapshots_via_analysis ON track_snapshots;
CREATE POLICY track_snapshots_via_analysis ON track_snapshots FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = track_snapshots.analysis_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = track_snapshots.analysis_id));

COMMENT ON TABLE track_snapshots IS 'Foto de cada trayectoria detectada (el mejor recorte del video) para que el cuerpo técnico reconozca al jugador y lo vincule a la plantilla.';
COMMENT ON COLUMN track_snapshots.analysis_id IS 'Análisis al que pertenece; se borra con él.';
COMMENT ON COLUMN track_snapshots.track_id IS 'Número de la trayectoria dentro del video (el mismo de detections.track_id).';
COMMENT ON COLUMN track_snapshots.frame_number IS 'Cuadro del video del que sale la foto.';
COMMENT ON COLUMN track_snapshots.timestamp IS 'Segundo del video del que sale la foto.';
COMMENT ON COLUMN track_snapshots.confidence IS 'Confianza de la detección de ese cuadro (0 a 1).';
COMMENT ON COLUMN track_snapshots.width IS 'Ancho de la foto en píxeles.';
COMMENT ON COLUMN track_snapshots.height IS 'Alto de la foto en píxeles (máximo 160).';
COMMENT ON COLUMN track_snapshots.image IS 'Foto en JPEG (unos pocos KB, máximo 60 000 bytes).';
COMMENT ON COLUMN track_snapshots.created_at IS 'Cuándo se guardó.';
