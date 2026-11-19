-- 0035 - A situation of the clip written by the staff, when none of the fixed ones fits.
--
--   videos.situation          adds OTHER to the fixed codes of migration 0020.
--   videos.situation_custom   the name the person writes for it ("Salida de arco corta", up to 30
--                             characters). Present only when situation is OTHER, and always then.
--
-- Additive: no row changes and the backend of before keeps working (it never writes OTHER).
-- Idempotent.

ALTER TABLE videos ADD COLUMN IF NOT EXISTS situation_custom VARCHAR(30);

DO $$
BEGIN
    -- The fixed list gains OTHER: drop the rule of 0020 and write it again with it.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'videos_situation_valid'
                     AND pg_get_constraintdef(oid) LIKE '%OTHER%') THEN
        ALTER TABLE videos DROP CONSTRAINT IF EXISTS videos_situation_valid;
        ALTER TABLE videos ADD CONSTRAINT videos_situation_valid CHECK (situation IS NULL OR situation IN (
            'BUILD_UP', 'POSITIONAL_ATTACK', 'COUNTER_ATTACK', 'DEFENSIVE_TRANSITION', 'PRESSING',
            'DEFENSIVE_BLOCK', 'SET_PIECE', 'OTHER'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'videos_situation_custom_valid') THEN
        ALTER TABLE videos ADD CONSTRAINT videos_situation_custom_valid CHECK (
            (situation IS DISTINCT FROM 'OTHER' AND situation_custom IS NULL)
            OR (situation IS NOT DISTINCT FROM 'OTHER' AND situation_custom IS NOT NULL
                AND length(btrim(situation_custom)) BETWEEN 1 AND 30));
    END IF;
END $$;

COMMENT ON COLUMN videos.situation IS 'Situación táctica que muestra el clip, elegida por una persona (BUILD_UP, POSITIONAL_ATTACK, COUNTER_ATTACK, DEFENSIVE_TRANSITION, PRESSING, DEFENSIVE_BLOCK, SET_PIECE, u OTHER si la escribe el cuerpo técnico). NULL: sin clasificar.';
COMMENT ON COLUMN videos.situation_custom IS 'Situación escrita por el cuerpo técnico cuando ninguna fija sirve (hasta 30 caracteres). Solo existe cuando situation es OTHER.';
