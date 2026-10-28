-- 0019 - How much of the video each indicator could judge.
--
--   tactical_indicators.samples        frames in which the indicator was measured (for indicators judged
--                                      in one phase, only the frames of that phase: e.g. while defending)
--   tactical_indicators.exceed_ratio   share of those frames on the wrong side of the threshold (0..1)
--
-- The AI only raises a possible problem with at least 8 frames and 50 % of them on the wrong side.
-- With these two columns the follow-up of a confirmed problem can tell "measured and it did not
-- appear" from "too few frames to judge". NULL in analyses stored before this migration: unknown.
--
-- Idempotent.

ALTER TABLE tactical_indicators ADD COLUMN IF NOT EXISTS samples INTEGER;
ALTER TABLE tactical_indicators ADD COLUMN IF NOT EXISTS exceed_ratio NUMERIC(5,4);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tactical_indicators_samples_valid') THEN
        ALTER TABLE tactical_indicators ADD CONSTRAINT tactical_indicators_samples_valid
            CHECK (samples IS NULL OR samples >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tactical_indicators_exceed_ratio_valid') THEN
        ALTER TABLE tactical_indicators ADD CONSTRAINT tactical_indicators_exceed_ratio_valid
            CHECK (exceed_ratio IS NULL OR exceed_ratio BETWEEN 0 AND 1);
    END IF;
END $$;

COMMENT ON COLUMN tactical_indicators.samples IS 'Cuadros en que se midió (solo los de su fase de juego, si tiene). NULL en análisis anteriores a 0019.';
COMMENT ON COLUMN tactical_indicators.exceed_ratio IS 'Proporción de esos cuadros del lado malo del umbral (0..1). NULL en análisis anteriores a 0019.';
