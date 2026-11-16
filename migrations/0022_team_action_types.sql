-- 0022 - Action types written by the team, and shorter texts for the plays.
--
--   team_action_types   besides the fixed types of the editor (salida de balón, presión...), the
--                       coach can write his own ("Saque de banda largo") and reuse it in any play.
--                       One name per team, compared without caring about upper or lower case.
--   tactical_plays      the name is at most 50 characters and the description at most 100 for the
--                       plays saved from now on (NOT VALID: older, longer ones stay as they are).
--
-- A play keeps the type as text in tactical_plays.action_type (a fixed code or one of these names),
-- so deleting a type from the list never changes the plays that already use it. Idempotent.

CREATE TABLE IF NOT EXISTS team_action_types (
    id VARCHAR(36) PRIMARY KEY,
    team_id VARCHAR(36) NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    name VARCHAR(40) NOT NULL CHECK (char_length(btrim(name)) BETWEEN 2 AND 40 AND name = btrim(name)),
    created_by VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_team_action_types_name ON team_action_types (team_id, lower(name));

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON team_action_types TO tactivision_app;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_tactical_plays_name_length') THEN
        ALTER TABLE tactical_plays ADD CONSTRAINT ck_tactical_plays_name_length
            CHECK (char_length(name) <= 50) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_tactical_plays_description_length') THEN
        ALTER TABLE tactical_plays ADD CONSTRAINT ck_tactical_plays_description_length
            CHECK (description IS NULL OR char_length(description) <= 100) NOT VALID;
    END IF;
END $$;

-- Row-Level Security: each team sees only its own types (same rule as tactical_plays).
ALTER TABLE team_action_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS team_action_types_team_isolation ON team_action_types;
CREATE POLICY team_action_types_team_isolation ON team_action_types FOR ALL
    USING (app_can_see_team(team_id)) WITH CHECK (app_can_see_team(team_id));

COMMENT ON TABLE team_action_types IS 'Tipos de acción escritos por el equipo para sus jugadas, además de los fijos del editor.';
COMMENT ON COLUMN team_action_types.id IS 'Identificador (UUID).';
COMMENT ON COLUMN team_action_types.team_id IS 'Equipo dueño del tipo.';
COMMENT ON COLUMN team_action_types.name IS 'Nombre del tipo de acción (2 a 40 caracteres), único por equipo sin distinguir mayúsculas.';
COMMENT ON COLUMN team_action_types.created_by IS 'Quién lo escribió.';
COMMENT ON COLUMN team_action_types.created_at IS 'Cuándo se creó.';
