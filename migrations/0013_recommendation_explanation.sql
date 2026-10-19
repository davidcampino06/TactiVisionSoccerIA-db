-- 0013 - Each possible tactical issue explained in football words, with a real frame that shows it.
--
-- The AI Service now sends, for every recommendation, what it saw (with the numbers in plain
-- words), what it means on the pitch, what a coaching staff could work on, and one real frame
-- (players, ball and a drawing of the rule) to show it on a pitch. It is kept whole as JSON, like
-- video_analyses.proximity_network: it is only read to show it. Old rows keep NULL. Idempotent.

ALTER TABLE ai_recommendations ADD COLUMN IF NOT EXISTS explanation TEXT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ai_recommendations_explanation_json') THEN
        -- Must be a JSON object with the "seen" text (the cast also rejects text that is not JSON).
        ALTER TABLE ai_recommendations ADD CONSTRAINT ai_recommendations_explanation_json
            CHECK (explanation IS NULL OR (explanation::jsonb ? 'seen'));
    END IF;
END $$;

COMMENT ON COLUMN ai_recommendations.explanation IS
    'JSON: explicación en lenguaje de fútbol (qué vio la IA, qué significa, qué trabajar) y un cuadro real que lo muestra.';
