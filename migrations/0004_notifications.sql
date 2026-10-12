-- 0004 - Notifications (the bell in the app).
-- Before, notifications lived only in the backend's memory and were lost on every restart.
-- Now each team event is stored once per team, and each user marks what he already read.
--
--   notifications       one row per event of a team (analysis finished, failed, tactical alert...)
--   notification_reads  who read what: (notification, user). No row = unread for that user.
--
-- Row-Level Security: a team only sees its own notifications (same rule as matches), and a user
-- only sees and writes his own read marks. Idempotent: it can be run more than once.

CREATE TABLE IF NOT EXISTS notifications (
    id VARCHAR(36) PRIMARY KEY,
    team_id VARCHAR(36) NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    event VARCHAR(40) NOT NULL
        CHECK (event IN ('ANALYSIS_COMPLETED', 'ANALYSIS_FAILED', 'ANALYSIS_CANCELLED', 'TACTICAL_ALERT',
                         'ANALYST_JOINED')),
    analysis_id VARCHAR(36) REFERENCES video_analyses(id) ON DELETE SET NULL,
    match_id VARCHAR(36) REFERENCES matches(id) ON DELETE SET NULL,
    message VARCHAR(500) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- The bell always asks for "the newest notifications of my team".
CREATE INDEX IF NOT EXISTS idx_notifications_team_created ON notifications (team_id, created_at DESC);

CREATE TABLE IF NOT EXISTS notification_reads (
    notification_id VARCHAR(36) NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    user_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    read_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (notification_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_notification_reads_user ON notification_reads (user_id);

-- The application role needs the same privileges as on the other tables (migration 0002).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON notifications, notification_reads TO tactivision_app;
    END IF;
END $$;

-- ------------------------------------------------------------------ Row-Level Security
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notifications_team_isolation ON notifications;
CREATE POLICY notifications_team_isolation ON notifications FOR ALL
    USING (app_can_see_team(team_id)) WITH CHECK (app_can_see_team(team_id));

DROP POLICY IF EXISTS notification_reads_owner ON notification_reads;
CREATE POLICY notification_reads_owner ON notification_reads FOR ALL
    USING (app_rls_bypass() OR (user_id = app_current_user()
           AND EXISTS (SELECT 1 FROM notifications n WHERE n.id = notification_reads.notification_id)))
    WITH CHECK (app_rls_bypass() OR (user_id = app_current_user()
           AND EXISTS (SELECT 1 FROM notifications n WHERE n.id = notification_reads.notification_id)));
