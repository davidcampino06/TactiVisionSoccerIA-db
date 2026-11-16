-- 0024 - The shirt number typed for a track is a real shirt number.
--
-- Since the staff types the number on the video (PUT /api/analyses/{id}/tracks/{n}/identity), every
-- detection of that track gets it in detections.player_number. The API accepts 0 to 99; this makes
-- the database say the same, so no other client can store a "250" or a "-1". NOT VALID: rows saved
-- before are not checked here (sql/verify_data.sql reports them, if any). Idempotent.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_detections_player_number') THEN
        ALTER TABLE detections ADD CONSTRAINT ck_detections_player_number
            CHECK (player_number IS NULL OR player_number BETWEEN 0 AND 99) NOT VALID;
    END IF;
END $$;

COMMENT ON COLUMN detections.player_number IS 'Dorsal (0 a 99) que una persona escribió para la trayectoria; lo comparten todas sus detecciones.';
