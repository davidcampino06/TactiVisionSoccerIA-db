-- 0003 - Player details.
-- Preferred foot for the squad screen. Nullable: existing players keep working without it.

ALTER TABLE players ADD COLUMN IF NOT EXISTS preferred_foot VARCHAR(10);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'players_preferred_foot_check') THEN
        ALTER TABLE players ADD CONSTRAINT players_preferred_foot_check
            CHECK (preferred_foot IS NULL OR preferred_foot IN ('RIGHT', 'LEFT', 'BOTH'));
    END IF;
END $$;
