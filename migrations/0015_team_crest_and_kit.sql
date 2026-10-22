-- 0015 - The team's crest and kit colour, and which detected team is "us" in each analysis.
--
--   teams.kit_color              usual shirt colour (#rrggbb). The app proposes it when a video is
--                                analysed; the coach can change it (away kit) or leave it empty.
--   team_crests                  the crest image, one per team. Its own table so the image (bytes)
--                                is not read with every team query nor copied by the audit trigger
--                                on teams. The backend re-encodes every upload as a 256 px PNG.
--   video_analyses.own_kit_color the colour given for that analysis (NULL = not given)
--   video_analyses.own_team      TEAM_A / TEAM_B: which detected team wears it (NULL = unknown)
--
-- The AI always separates the two teams from the video alone; the colour only says which one is
-- the user's team, and only when it is clearly closer to one of them. Idempotent.

ALTER TABLE teams ADD COLUMN IF NOT EXISTS kit_color VARCHAR(7);
ALTER TABLE video_analyses ADD COLUMN IF NOT EXISTS own_kit_color VARCHAR(7);
ALTER TABLE video_analyses ADD COLUMN IF NOT EXISTS own_team VARCHAR(10);

CREATE TABLE IF NOT EXISTS team_crests (
    team_id VARCHAR(36) PRIMARY KEY REFERENCES teams(id) ON DELETE CASCADE,
    content_type VARCHAR(20) NOT NULL CHECK (content_type = 'image/png'),
    image BYTEA NOT NULL CHECK (octet_length(image) BETWEEN 1 AND 300000),
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'teams_kit_color_hex') THEN
        ALTER TABLE teams ADD CONSTRAINT teams_kit_color_hex
            CHECK (kit_color IS NULL OR kit_color ~ '^#[0-9a-f]{6}$');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'video_analyses_own_team_valid') THEN
        ALTER TABLE video_analyses ADD CONSTRAINT video_analyses_own_team_valid CHECK (
            (own_kit_color IS NULL OR own_kit_color ~ '^#[0-9a-f]{6}$')
            AND (own_team IS NULL OR own_team IN ('TEAM_A', 'TEAM_B')));
    END IF;
    -- The application role needs the same privileges as on the other tables (migration 0002).
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON team_crests TO tactivision_app;
    END IF;
END $$;

-- Row-Level Security: only people of the team see or change its crest (same rule as matches).
ALTER TABLE team_crests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS team_crests_team_isolation ON team_crests;
CREATE POLICY team_crests_team_isolation ON team_crests FOR ALL
    USING (app_can_see_team(team_id)) WITH CHECK (app_can_see_team(team_id));

COMMENT ON COLUMN teams.kit_color IS 'Color habitual de la camiseta del equipo (#rrggbb); se propone al analizar un video.';
COMMENT ON TABLE team_crests IS 'Escudo del equipo: una imagen PNG de 256 px por equipo, re-codificada por el backend.';
COMMENT ON COLUMN team_crests.team_id IS 'Equipo dueño del escudo.';
COMMENT ON COLUMN team_crests.content_type IS 'Tipo de la imagen guardada (siempre image/png).';
COMMENT ON COLUMN team_crests.image IS 'Bytes de la imagen PNG (máximo 300 KB).';
COMMENT ON COLUMN team_crests.updated_at IS 'Cuándo se cambió el escudo por última vez.';
COMMENT ON COLUMN video_analyses.own_kit_color IS 'Color de camiseta de tu equipo indicado para este análisis (#rrggbb); vacío si no se indicó.';
COMMENT ON COLUMN video_analyses.own_team IS 'Cuál de los equipos detectados es el tuyo (TEAM_A o TEAM_B); vacío si no se pudo saber.';
