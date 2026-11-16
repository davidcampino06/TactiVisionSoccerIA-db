-- 0030 - Tracks whose shirt is of no team: possible referee or goalkeeper.
--
--   track_role_suggestions   the AI (role_suggestions.py) groups by shirt colour the people whose
--                            kit is far from both teams. Two or more of a kit on screen at once is
--                            the refereeing crew (REFEREE); only one at a time can be a goalkeeper
--                            or the referee (GOALKEEPER_OR_REFEREE). Tracks of the same kit share
--                            kit_group, so identifying one tells who the others are.
--
-- The decision is not stored here: marking the referee goes to track_labels (migration 0023) and a
-- goalkeeper gets his shirt number like any player. A person can dismiss a suggestion that is wrong
-- (dismissed_at), for example somebody on the touchline. Rows are deleted with their analysis.
-- Idempotent.

CREATE TABLE IF NOT EXISTS track_role_suggestions (
    analysis_id VARCHAR(36) NOT NULL REFERENCES video_analyses(id) ON DELETE CASCADE,
    track_id INTEGER NOT NULL CHECK (track_id >= 0),
    suggestion VARCHAR(21) NOT NULL CHECK (suggestion IN ('REFEREE', 'GOALKEEPER_OR_REFEREE')),
    kit_group SMALLINT NOT NULL CHECK (kit_group >= 1),
    kit_color CHAR(7) NOT NULL CHECK (kit_color ~ '^#[0-9a-f]{6}$'),
    kit_tracks SMALLINT NOT NULL CHECK (kit_tracks >= 1),
    confidence DECIMAL(4, 3) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    reason VARCHAR(300) NOT NULL CHECK (length(trim(reason)) > 0),
    dismissed_by VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
    dismissed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (analysis_id, track_id),
    CONSTRAINT ck_track_role_suggestions_dismissed CHECK (dismissed_by IS NULL OR dismissed_at IS NOT NULL)
);

-- The tracks of one kit, in one analysis (the app shows them together).
CREATE INDEX IF NOT EXISTS idx_track_role_suggestions_kit ON track_role_suggestions (analysis_id, kit_group);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON track_role_suggestions TO tactivision_app;
    END IF;
END $$;

-- Row-Level Security: visible to whoever can see the analysis (same rule as track_labels).
ALTER TABLE track_role_suggestions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS track_role_suggestions_via_analysis ON track_role_suggestions;
CREATE POLICY track_role_suggestions_via_analysis ON track_role_suggestions FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = track_role_suggestions.analysis_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = track_role_suggestions.analysis_id));

COMMENT ON TABLE track_role_suggestions IS 'Trayectorias con una camiseta de ningún equipo, agrupadas por color: posible árbitro o arquero (sugerencia de la IA).';
COMMENT ON COLUMN track_role_suggestions.analysis_id IS 'Análisis al que pertenece; se borra con él.';
COMMENT ON COLUMN track_role_suggestions.track_id IS 'Trayectoria (detections.track_id).';
COMMENT ON COLUMN track_role_suggestions.suggestion IS 'REFEREE (varias personas a la vez con esa camiseta) o GOALKEEPER_OR_REFEREE (una sola a la vez).';
COMMENT ON COLUMN track_role_suggestions.kit_group IS 'Grupo de camiseta dentro del análisis: las trayectorias del mismo grupo llevan la misma.';
COMMENT ON COLUMN track_role_suggestions.kit_color IS 'Color medido de esa camiseta (#rrggbb).';
COMMENT ON COLUMN track_role_suggestions.kit_tracks IS 'Cuántas trayectorias llevan esa camiseta.';
COMMENT ON COLUMN track_role_suggestions.confidence IS 'Confianza de la sugerencia (0 a 1).';
COMMENT ON COLUMN track_role_suggestions.reason IS 'Por qué se sugiere, en palabras.';
COMMENT ON COLUMN track_role_suggestions.dismissed_by IS 'Quién la descartó.';
COMMENT ON COLUMN track_role_suggestions.dismissed_at IS 'Cuándo se descartó; NULL si sigue vigente.';
COMMENT ON COLUMN track_role_suggestions.created_at IS 'Cuándo se guardó la sugerencia.';
