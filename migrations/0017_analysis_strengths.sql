-- 0017 - What the team did well in each analysis (strengths), next to the possible problems.
--
--   analysis_strengths   one row per strength found by the AI (tactical_strengths.py in the AI
--                        repo): which team, what (code and title), the evidence with its numbers,
--                        how confident the AI is, the indicator it comes from and the explanation
--                        in football words (JSON: seen, meaning, keep and an example frame).
--
-- A strength is information, not an alert: it has no review status and does not go to the bell or
-- to the review queue. It belongs to the analysis and is deleted with it. Idempotent.

CREATE TABLE IF NOT EXISTS analysis_strengths (
    id VARCHAR(36) PRIMARY KEY,
    analysis_id VARCHAR(36) NOT NULL REFERENCES video_analyses(id) ON DELETE CASCADE,
    team VARCHAR(10) NOT NULL CHECK (team IN ('TEAM_A', 'TEAM_B', 'MATCH')),
    code VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    evidence TEXT NOT NULL,
    confidence DECIMAL(10, 4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    indicator VARCHAR(100),
    explanation TEXT CHECK (explanation IS NULL OR explanation::jsonb ? 'seen'),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_analysis_strengths_analysis ON analysis_strengths (analysis_id);

DO $$
BEGIN
    -- The application role needs the same privileges as on the other tables (migration 0002).
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON analysis_strengths TO tactivision_app;
    END IF;
END $$;

-- Row-Level Security: visible to whoever can see the analysis (same rule as tactical_indicators).
ALTER TABLE analysis_strengths ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS strengths_via_analysis ON analysis_strengths;
CREATE POLICY strengths_via_analysis ON analysis_strengths FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = analysis_strengths.analysis_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM video_analyses va WHERE va.id = analysis_strengths.analysis_id));

COMMENT ON TABLE analysis_strengths IS 'Lo que el equipo hizo bien en cada análisis (fortalezas), con su evidencia y explicación.';
COMMENT ON COLUMN analysis_strengths.id IS 'Identificador de la fortaleza.';
COMMENT ON COLUMN analysis_strengths.analysis_id IS 'Análisis al que pertenece; se borra con él.';
COMMENT ON COLUMN analysis_strengths.team IS 'TEAM_A, TEAM_B o MATCH (métrica del partido).';
COMMENT ON COLUMN analysis_strengths.code IS 'Regla que la encontró (LINES_TOGETHER, NOBODY_ISOLATED, PRESSURE_ON_BALL, ATTACKING_DEPTH).';
COMMENT ON COLUMN analysis_strengths.title IS 'Título en español, por ejemplo «Líneas juntas al defender».';
COMMENT ON COLUMN analysis_strengths.evidence IS 'Los números que la sostienen (porcentaje de cuadros del lado bueno y promedio).';
COMMENT ON COLUMN analysis_strengths.confidence IS 'Confianza de 0 a 1 (constancia, muestra, detección, separación de equipos y fiabilidad de la regla).';
COMMENT ON COLUMN analysis_strengths.indicator IS 'Indicador del que sale, por ejemplo team_a.defensive_midfield_distance.';
COMMENT ON COLUMN analysis_strengths.explanation IS 'JSON: qué se vio, qué significa, cómo mantenerlo y un cuadro de ejemplo para dibujar en la cancha.';
COMMENT ON COLUMN analysis_strengths.created_at IS 'Cuándo se guardó.';
