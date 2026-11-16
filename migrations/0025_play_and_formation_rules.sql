-- 0025 - Two rules the API already applies, now also in the database.
--
--   tactical_plays.action_type   at most 40 characters: a fixed code (BUILD_UP...) or a type the team
--                                wrote (team_action_types.name, 2 to 40 characters).
--   formations.name              when it is a system written with numbers (custom formations of the
--                                tactical editor), 2 to 5 lines of 1 to 6 players that add up to 10
--                                outfield players: 3-4-2-1 is valid, 4-4-3 or 7-2-1 are not. Names
--                                that are not numbers ("Rombo") are left as they are.
--
-- Both are NOT VALID: rows saved before are not checked here (sql/verify_data.sql reports them).
-- formation_name_is_valid() is IMMUTABLE so the CHECK can use it. Idempotent.

CREATE OR REPLACE FUNCTION formation_name_is_valid(formation_name TEXT) RETURNS BOOLEAN
    LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT formation_name !~ '^[0-9]+(-[0-9]+)*$'
        OR (SELECT count(*) BETWEEN 2 AND 5 AND bool_and(line::int BETWEEN 1 AND 6) AND sum(line::int) = 10
            FROM regexp_split_to_table(formation_name, '-') AS line)
$$;

COMMENT ON FUNCTION formation_name_is_valid(TEXT) IS
    'Verdadero si el nombre no es un sistema numérico, o si lo es con 2 a 5 líneas de 1 a 6 jugadores que suman 10.';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_tactical_plays_action_type_length') THEN
        ALTER TABLE tactical_plays ADD CONSTRAINT ck_tactical_plays_action_type_length
            CHECK (action_type IS NULL OR char_length(action_type) <= 40) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_formations_name_valid') THEN
        ALTER TABLE formations ADD CONSTRAINT ck_formations_name_valid
            CHECK (formation_name_is_valid(name)) NOT VALID;
    END IF;
END $$;
