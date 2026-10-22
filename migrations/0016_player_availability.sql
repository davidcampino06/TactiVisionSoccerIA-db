-- 0016 - Why a player is not available and when he is expected back.
--
--   players.status             + 'UNAVAILABLE': personal reasons or any other absence (a trip,
--                              studies, a family matter), next to INJURED and SUSPENDED.
--   players.availability_note  what happened, in the coach's words ("esguince de tobillo",
--                              "doble amarilla, 1 fecha", "viaje familiar")
--   players.expected_return    the day he should be back; the bell reminds the team that day
--   players.return_notified_on the expected_return already reminded (so it is reminded once)
--   notifications.event        + 'PLAYER_RETURN_DUE'
--
-- Note and return date only make sense while the player is unavailable: the rule below keeps them
-- empty for available or withdrawn players. Nothing changes the status by itself: the coach decides
-- when the player is back. Idempotent.

ALTER TABLE players ADD COLUMN IF NOT EXISTS availability_note VARCHAR(255);
ALTER TABLE players ADD COLUMN IF NOT EXISTS expected_return DATE;
ALTER TABLE players ADD COLUMN IF NOT EXISTS return_notified_on DATE;

DO $$
BEGIN
    ALTER TABLE players DROP CONSTRAINT IF EXISTS players_status_valid;
    ALTER TABLE players ADD CONSTRAINT players_status_valid
        CHECK (status IN ('ACTIVE', 'INJURED', 'SUSPENDED', 'UNAVAILABLE', 'INACTIVE'));

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'players_availability_only_when_unavailable') THEN
        ALTER TABLE players ADD CONSTRAINT players_availability_only_when_unavailable CHECK (
            status IN ('INJURED', 'SUSPENDED', 'UNAVAILABLE')
            OR (availability_note IS NULL AND expected_return IS NULL));
    END IF;

    ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_event_check;
    ALTER TABLE notifications ADD CONSTRAINT notifications_event_check
        CHECK (event IN ('ANALYSIS_COMPLETED', 'ANALYSIS_FAILED', 'ANALYSIS_CANCELLED', 'TACTICAL_ALERT',
                         'ANALYST_JOINED', 'PLAYER_RETURN_DUE'));
END $$;

-- "Who comes back today?" is asked often (with the bell); only unavailable players with a date matter.
CREATE INDEX IF NOT EXISTS idx_players_expected_return ON players (team_id, expected_return)
    WHERE expected_return IS NOT NULL;

COMMENT ON COLUMN players.status IS 'ACTIVE, INJURED, SUSPENDED, UNAVAILABLE (motivo personal u otro) o INACTIVE (de baja).';
COMMENT ON COLUMN players.availability_note IS 'Motivo de la ausencia, escrito por el entrenador (lesión, sanción, motivo personal).';
COMMENT ON COLUMN players.expected_return IS 'Fecha estimada de regreso; ese día la campana lo recuerda.';
COMMENT ON COLUMN players.return_notified_on IS 'Fecha de regreso que ya se recordó (para avisar una sola vez).';
