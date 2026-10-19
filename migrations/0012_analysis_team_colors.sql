-- 0012 - Shirt colour of each team in an analysis, and warnings without a length limit.
--
-- The AI Service names the teams TEAM_A / TEAM_B by where they appear in the image and returns
-- the shirt colour of each one, but the colour was not stored: the app said "Equipo A" without
-- saying which team that was. The warnings were cut at 255 characters, so the last ones (for
-- example "this team's defensive shape was not judged") could be lost. Idempotent.

ALTER TABLE video_analyses ADD COLUMN IF NOT EXISTS team_a_color VARCHAR(7);
ALTER TABLE video_analyses ADD COLUMN IF NOT EXISTS team_b_color VARCHAR(7);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'video_analyses_team_colors_hex') THEN
        ALTER TABLE video_analyses ADD CONSTRAINT video_analyses_team_colors_hex CHECK (
            (team_a_color IS NULL OR team_a_color ~ '^#[0-9a-f]{6}$')
            AND (team_b_color IS NULL OR team_b_color ~ '^#[0-9a-f]{6}$'));
    END IF;
END $$;

ALTER TABLE video_analyses ALTER COLUMN warning_message TYPE TEXT;

COMMENT ON COLUMN video_analyses.team_a_color IS
    'Color de camiseta del Equipo A según la IA (#rrggbb); vacío en análisis antiguos o de simulación sin color.';
COMMENT ON COLUMN video_analyses.team_b_color IS
    'Color de camiseta del Equipo B según la IA (#rrggbb); vacío en análisis antiguos o de simulación sin color.';
COMMENT ON COLUMN video_analyses.warning_message IS
    'Advertencias del análisis (todas, sin recortar) o el motivo del fallo.';
