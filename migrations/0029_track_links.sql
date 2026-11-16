-- 0029 - Tracks that look like the same player cut in two, and what a person decided.
--
--   track_links   the AI (track_stitching.py) suggests that track to_track continues track
--                 from_track: the player was hidden or left the picture for a moment and the tracker
--                 gave him a new number. Each suggestion keeps its reasons (gap in seconds, distance
--                 to where he should be, shirt colour, team) and a status: SUGGESTED until a person
--                 ACCEPTS it (both tracks are one player, so a shirt number given to one is given to
--                 the other) or REJECTS it.
--
-- A track continues at most one track and is continued by at most one (the AI chooses one-to-one,
-- the keys enforce it). Rows are deleted with their analysis. Idempotent.

CREATE TABLE IF NOT EXISTS track_links (
    analysis_id VARCHAR(36) NOT NULL REFERENCES video_analyses(id) ON DELETE CASCADE,
    from_track INTEGER NOT NULL CHECK (from_track >= 0),
    to_track INTEGER NOT NULL CHECK (to_track >= 0),
    from_last_frame INTEGER NOT NULL CHECK (from_last_frame >= 0),
    to_first_frame INTEGER NOT NULL,
    gap_seconds DECIMAL(6, 3) NOT NULL CHECK (gap_seconds > 0),
    distance_heights DECIMAL(6, 3) NOT NULL CHECK (distance_heights >= 0),
    color_distance DECIMAL(7, 2) CHECK (color_distance >= 0),
    same_team BOOLEAN,
    confidence DECIMAL(4, 3) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    status VARCHAR(9) NOT NULL DEFAULT 'SUGGESTED' CHECK (status IN ('SUGGESTED', 'ACCEPTED', 'REJECTED')),
    decided_by VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
    decided_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (analysis_id, from_track),
    CONSTRAINT uq_track_links_to UNIQUE (analysis_id, to_track),
    CONSTRAINT ck_track_links_two_tracks CHECK (from_track <> to_track),
    -- The new track starts after the old one ends: never both on screen at once.
    CONSTRAINT ck_track_links_order CHECK (to_first_frame > from_last_frame),
    -- A decision says when it was taken; a suggestion has no decision yet.
    CONSTRAINT ck_track_links_decision CHECK ((status = 'SUGGESTED') = (decided_at IS NULL)),
    CONSTRAINT ck_track_links_decided_by CHECK (decided_by IS NULL OR decided_at IS NOT NULL)
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON track_links TO tactivision_app;
    END IF;
END $$;

-- Row-Level Security: visible to whoever can see the analysis (same rule as track_labels).
ALTER TABLE track_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS track_links_via_analysis ON track_links;
CREATE POLICY track_links_via_analysis ON track_links FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = track_links.analysis_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = track_links.analysis_id));

COMMENT ON TABLE track_links IS 'Pares de trayectorias que parecen el mismo jugador cortado en dos (sugeridos por la IA) y la decisión de una persona.';
COMMENT ON COLUMN track_links.analysis_id IS 'Análisis al que pertenece; se borra con él.';
COMMENT ON COLUMN track_links.from_track IS 'Trayectoria que termina (detections.track_id).';
COMMENT ON COLUMN track_links.to_track IS 'Trayectoria que empieza después y sería el mismo jugador.';
COMMENT ON COLUMN track_links.from_last_frame IS 'Último cuadro en que se ve from_track.';
COMMENT ON COLUMN track_links.to_first_frame IS 'Primer cuadro en que se ve to_track (siempre después).';
COMMENT ON COLUMN track_links.gap_seconds IS 'Segundos en que el jugador no se vio (máximo 1.5 en la IA).';
COMMENT ON COLUMN track_links.distance_heights IS 'Distancia entre donde debía estar y donde reaparece, en alturas de la caja.';
COMMENT ON COLUMN track_links.color_distance IS 'Diferencia del color de camiseta (Lab); NULL si no se midió.';
COMMENT ON COLUMN track_links.same_team IS 'TRUE si las dos tienen el mismo equipo; NULL si alguna no tiene equipo.';
COMMENT ON COLUMN track_links.confidence IS 'Confianza de la sugerencia (0 a 1).';
COMMENT ON COLUMN track_links.status IS 'SUGGESTED (sin revisar), ACCEPTED (es el mismo jugador) o REJECTED.';
COMMENT ON COLUMN track_links.decided_by IS 'Quién la aceptó o rechazó.';
COMMENT ON COLUMN track_links.decided_at IS 'Cuándo se decidió; NULL mientras es una sugerencia.';
COMMENT ON COLUMN track_links.created_at IS 'Cuándo se guardó la sugerencia.';
