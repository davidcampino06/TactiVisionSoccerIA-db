-- 0018 - What the coaching staff says about the AI's output, and which strengths they confirm.
--
--   recommendation_notes        what the analyst (or the coach) reads in a possible problem, written by
--                               a person and signed: "pasa en las transiciones, el 8 llega tarde".
--                               Several per problem; each one rings the team's bell.
--   analysis_strengths.status   GENERATED / CONFIRMED / DISMISSED, like the problems: the match plan
--                               only shows what a person confirmed.
--   notifications.event         + 'RECOMMENDATION_NOTE'
--
-- Idempotent.

CREATE TABLE IF NOT EXISTS recommendation_notes (
    id VARCHAR(36) PRIMARY KEY,
    recommendation_id VARCHAR(36) NOT NULL REFERENCES ai_recommendations(id) ON DELETE CASCADE,
    author_id VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
    text VARCHAR(1000) NOT NULL CHECK (length(btrim(text)) BETWEEN 1 AND 1000),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_recommendation_notes_recommendation ON recommendation_notes (recommendation_id, created_at);

ALTER TABLE analysis_strengths ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'GENERATED';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'analysis_strengths_status_valid') THEN
        ALTER TABLE analysis_strengths ADD CONSTRAINT analysis_strengths_status_valid
            CHECK (status IN ('GENERATED', 'CONFIRMED', 'DISMISSED'));
    END IF;

    ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_event_check;
    ALTER TABLE notifications ADD CONSTRAINT notifications_event_check
        CHECK (event IN ('ANALYSIS_COMPLETED', 'ANALYSIS_FAILED', 'ANALYSIS_CANCELLED', 'TACTICAL_ALERT',
                         'ANALYST_JOINED', 'PLAYER_RETURN_DUE', 'RECOMMENDATION_NOTE'));

    -- The application role needs the same privileges as on the other tables (migration 0002).
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON recommendation_notes TO tactivision_app;
    END IF;
END $$;

-- Row-Level Security: visible to whoever can see the problem (same rule as recommendation_indicators).
ALTER TABLE recommendation_notes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notes_via_recommendation ON recommendation_notes;
CREATE POLICY notes_via_recommendation ON recommendation_notes FOR ALL
    USING (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM ai_recommendations r WHERE r.id = recommendation_notes.recommendation_id))
    WITH CHECK (app_rls_bypass() OR EXISTS (
        SELECT 1 FROM ai_recommendations r WHERE r.id = recommendation_notes.recommendation_id));

COMMENT ON TABLE recommendation_notes IS 'Notas del cuerpo técnico sobre un posible problema: lo que una persona interpreta, firmado.';
COMMENT ON COLUMN recommendation_notes.id IS 'Identificador de la nota.';
COMMENT ON COLUMN recommendation_notes.recommendation_id IS 'Posible problema al que se refiere; se borra con él.';
COMMENT ON COLUMN recommendation_notes.author_id IS 'Quién la escribió (analista o entrenador); queda vacío si el usuario se elimina.';
COMMENT ON COLUMN recommendation_notes.text IS 'La nota (de 1 a 1000 caracteres).';
COMMENT ON COLUMN recommendation_notes.created_at IS 'Cuándo se escribió.';
COMMENT ON COLUMN recommendation_notes.updated_at IS 'Cuándo se editó por última vez.';
COMMENT ON COLUMN analysis_strengths.status IS 'GENERATED (sin revisar), CONFIRMED o DISMISSED: el plan de partido solo usa las confirmadas.';
