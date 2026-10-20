-- 0014 - A user can delete notifications from his bell.
--
-- Notifications belong to the team (one row per event, migration 0004) and every user keeps his
-- own read marks in notification_reads. Deleting is personal too: when the analyst deletes "the
-- analysis finished", the coach still sees it. So deleting does not remove the team's row: it
-- marks it as hidden for that user (hidden_at). A hidden notification is also read. Idempotent.

ALTER TABLE notification_reads ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMP;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notification_reads_hidden_after_read') THEN
        ALTER TABLE notification_reads ADD CONSTRAINT notification_reads_hidden_after_read
            CHECK (hidden_at IS NULL OR hidden_at >= read_at);
    END IF;
END $$;

COMMENT ON COLUMN notification_reads.hidden_at IS
    'Cuándo el usuario eliminó la notificación de su campana; vacío si la sigue viendo. Los demás del equipo la siguen viendo.';
COMMENT ON TABLE notification_reads IS 'Qué notificaciones leyó (o eliminó de su campana) cada usuario.';
