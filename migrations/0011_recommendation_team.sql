-- 0011 - Which team each possible tactical issue is about.
--
-- The AI Service already says it (TEAM_A, TEAM_B or MATCH for match-level metrics) but the value
-- was not stored, so when both teams had the same issue the app showed two identical cards.
-- Rows from before this migration keep NULL (unknown). Idempotent.

ALTER TABLE ai_recommendations ADD COLUMN IF NOT EXISTS team VARCHAR(20);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ai_recommendations_team_valid') THEN
        ALTER TABLE ai_recommendations ADD CONSTRAINT ai_recommendations_team_valid
            CHECK (team IS NULL OR team IN ('TEAM_A', 'TEAM_B', 'MATCH'));
    END IF;
END $$;

COMMENT ON COLUMN ai_recommendations.team IS
    'Equipo al que se refiere: TEAM_A, TEAM_B o MATCH (métrica del partido); vacío en análisis antiguos.';
