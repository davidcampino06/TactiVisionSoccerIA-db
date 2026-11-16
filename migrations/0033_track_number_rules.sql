-- 0033 - A track number is never negative, in every table that names a track.
--
-- The tracker numbers the people it follows from 1 up, and a detection the tracker did not follow
-- has no number (NULL). track_links and track_role_suggestions (migrations 0029 and 0030) already
-- reject a negative track; detections, track_snapshots and track_labels now say the same, so the
-- tables that point to one track cannot disagree on what a valid one is. NOT VALID: rows saved before
-- are not checked here (sql/verify_data.sql counts them, if any). Idempotent.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_detections_track_id') THEN
        ALTER TABLE detections ADD CONSTRAINT ck_detections_track_id
            CHECK (track_id IS NULL OR track_id >= 0) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_track_snapshots_track_id') THEN
        ALTER TABLE track_snapshots ADD CONSTRAINT ck_track_snapshots_track_id CHECK (track_id >= 0) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_track_labels_track_id') THEN
        ALTER TABLE track_labels ADD CONSTRAINT ck_track_labels_track_id CHECK (track_id >= 0) NOT VALID;
    END IF;
END $$;

COMMENT ON COLUMN detections.track_id IS 'Número de la trayectoria (0 o más) que dio el tracker; NULL si no siguió a esa persona.';
