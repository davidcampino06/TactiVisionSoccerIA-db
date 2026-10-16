-- 0006 - Audit log: who changed what and when, written by triggers.
--
-- Every INSERT, UPDATE and DELETE on the main tables leaves one row in audit_log:
--   table_name, row_id, action, changed_at, changed_by and changed_fields (JSONB):
--     INSERT -> the new row, DELETE -> the old row, UPDATE -> only the columns that changed
--     as {"column": {"old": ..., "new": ...}}.
-- changed_by is app.current_user_id, the user the backend sets in each transaction (migration 0002,
-- DATABASE_RLS=true); it is NULL for work without a user (scripts, background jobs).
-- Secrets are never copied: password_hash is left out (an UPDATE only says "changed"), and the large
-- JSON documents (reports.snapshot_data, play configurations) are left out too.
--
-- The trigger function is SECURITY DEFINER: the application role (tactivision_app) cannot read or
-- write audit_log directly (RLS on, no policy), only the triggers can write it. Idempotent.

CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(63) NOT NULL,
    row_id VARCHAR(36),
    action VARCHAR(6) NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    changed_by VARCHAR(36),
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_fields JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_log_row ON audit_log (table_name, row_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_changed_at ON audit_log (changed_at DESC);

CREATE OR REPLACE FUNCTION audit_row_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    hidden CONSTANT text[] := ARRAY['password_hash', 'snapshot_data', 'configuration_data'];
    old_row jsonb;
    new_row jsonb;
    diff jsonb := '{}'::jsonb;
    column_name text;
BEGIN
    IF TG_OP <> 'INSERT' THEN old_row := to_jsonb(OLD) - hidden; END IF;
    IF TG_OP <> 'DELETE' THEN new_row := to_jsonb(NEW) - hidden; END IF;

    IF TG_OP = 'UPDATE' THEN
        FOR column_name IN SELECT jsonb_object_keys(new_row) LOOP
            IF new_row -> column_name IS DISTINCT FROM old_row -> column_name THEN
                diff := diff || jsonb_build_object(column_name,
                    jsonb_build_object('old', old_row -> column_name, 'new', new_row -> column_name));
            END IF;
        END LOOP;
        IF to_jsonb(NEW) ->> 'password_hash' IS DISTINCT FROM to_jsonb(OLD) ->> 'password_hash' THEN
            diff := diff || '{"password_hash": "changed"}'::jsonb;
        END IF;
        IF diff = '{}'::jsonb THEN
            RETURN NULL;  -- nothing really changed: no audit row
        END IF;
    END IF;

    INSERT INTO audit_log (table_name, row_id, action, changed_by, changed_fields)
    VALUES (TG_TABLE_NAME,
            COALESCE(new_row ->> 'id', old_row ->> 'id'),
            TG_OP,
            NULLIF(current_setting('app.current_user_id', true), ''),
            CASE TG_OP WHEN 'INSERT' THEN new_row WHEN 'DELETE' THEN old_row ELSE diff END);
    RETURN NULL;
END;
$$;

DO $$
DECLARE
    audited text;
BEGIN
    FOREACH audited IN ARRAY ARRAY['users', 'teams', 'players', 'matches', 'videos', 'ai_recommendations',
                                    'tactical_plays', 'reports'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_%1$s ON %1$I', audited);
        EXECUTE format('CREATE TRIGGER trg_audit_%1$s AFTER INSERT OR UPDATE OR DELETE ON %1$I '
                       'FOR EACH ROW EXECUTE FUNCTION audit_row_change()', audited);
    END LOOP;
END $$;

-- Only the database owner (and the triggers) can see the audit trail.
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        REVOKE ALL ON audit_log FROM tactivision_app;
        REVOKE ALL ON SEQUENCE audit_log_id_seq FROM tactivision_app;
    END IF;
END $$;
