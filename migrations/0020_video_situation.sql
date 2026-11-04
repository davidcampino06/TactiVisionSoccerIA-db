-- 0020 - Which tactical situation each clip shows, to study clips by situation (clip library).
--
--   videos.situation        the situation a person says the clip shows, from the point of view of
--                           the team: BUILD_UP (salida de balón), POSITIONAL_ATTACK (ataque
--                           organizado), COUNTER_ATTACK (transición ofensiva), DEFENSIVE_TRANSITION
--                           (transición defensiva), PRESSING (presión alta), DEFENSIVE_BLOCK (bloque
--                           defensivo), SET_PIECE (balón parado). NULL: not classified yet.
--   videos.situation_note   a short note of the staff about the clip ("salida por la izquierda,
--                           minuto 23"), optional.
--
-- Chosen by a person, never by the AI: with the ball seen in few frames the AI cannot tell these
-- situations apart reliably. The codes of the play types of the tactical board are reused where
-- they mean the same, so a clip and a play of the same situation can be shown together.
--
-- Idempotent.

ALTER TABLE videos ADD COLUMN IF NOT EXISTS situation VARCHAR(30);
ALTER TABLE videos ADD COLUMN IF NOT EXISTS situation_note VARCHAR(200);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'videos_situation_valid') THEN
        ALTER TABLE videos ADD CONSTRAINT videos_situation_valid CHECK (situation IS NULL OR situation IN (
            'BUILD_UP', 'POSITIONAL_ATTACK', 'COUNTER_ATTACK', 'DEFENSIVE_TRANSITION', 'PRESSING',
            'DEFENSIVE_BLOCK', 'SET_PIECE'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'videos_situation_note_valid') THEN
        ALTER TABLE videos ADD CONSTRAINT videos_situation_note_valid
            CHECK (situation_note IS NULL OR length(btrim(situation_note)) BETWEEN 1 AND 200);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_videos_situation ON videos (situation) WHERE situation IS NOT NULL;

COMMENT ON COLUMN videos.situation IS 'Situación táctica que muestra el clip, elegida por una persona (BUILD_UP, POSITIONAL_ATTACK, COUNTER_ATTACK, DEFENSIVE_TRANSITION, PRESSING, DEFENSIVE_BLOCK, SET_PIECE). NULL: sin clasificar.';
COMMENT ON COLUMN videos.situation_note IS 'Nota corta del cuerpo técnico sobre el clip (opcional).';
