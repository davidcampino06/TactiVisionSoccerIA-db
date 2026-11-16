-- 0027 - Fingerprint of each applied migration.
--
-- schema_migrations only said WHICH migrations were applied. If someone edits a migration after it
-- ran in Neon, the database and the repository disagree and nobody notices. scripts/apply_migrations.py
-- now stores the SHA-256 of each file when it applies it (line endings normalised, so a Windows
-- checkout gives the same value) and refuses to go on when an applied file changed.
-- Migrations applied before this one get their fingerprint the next time the script runs. Idempotent.

ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS checksum CHAR(64);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_schema_migrations_checksum') THEN
        ALTER TABLE schema_migrations ADD CONSTRAINT ck_schema_migrations_checksum
            CHECK (checksum IS NULL OR checksum ~ '^[0-9a-f]{64}$');
    END IF;
END $$;

COMMENT ON COLUMN schema_migrations.checksum IS 'SHA-256 del archivo de la migración cuando se aplicó (fin de línea normalizado); detecta migraciones editadas después de aplicarse.';
