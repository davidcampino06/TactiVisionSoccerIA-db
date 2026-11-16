-- 0031 - Audit of who identified the tracks: labels, accepted or rejected links, dismissed roles.
--
-- The audit trigger (migration 0006) names each row by its "id" column. The track tables have no
-- such column: a row is (analysis, track). Now the trigger can be given the columns that name the
-- row, as trigger arguments, and it writes them joined by "/" in audit_log.row_id, for example
-- "4f1c...-9a/31". row_id grows to 80 characters for that (a 36-character analysis id plus a track
-- number). Tables with an "id" keep working exactly as before.
--
-- Audited from now on: track_labels (referee / outsider marks), track_links (the decision on each
-- suggested link) and track_role_suggestions (a dismissed suggestion). The shirt numbers are on
-- detections, which are written by the analysis in bulk and are not audited. Idempotent.

ALTER TABLE audit_log ALTER COLUMN row_id TYPE VARCHAR(80);

CREATE OR REPLACE FUNCTION audit_row_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    hidden CONSTANT text[] := ARRAY['password_hash', 'snapshot_data', 'configuration_data'];
    old_row jsonb;
    new_row jsonb;
    diff jsonb := '{}'::jsonb;
    column_name text;
    key_row jsonb;
    row_name text;
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

    -- The row is named by the trigger arguments (its key columns) or, without arguments, by "id".
    key_row := COALESCE(new_row, old_row);
    IF TG_NARGS > 0 THEN
        SELECT string_agg(key_row ->> TG_ARGV[i], '/' ORDER BY i) INTO row_name
        FROM generate_series(0, TG_NARGS - 1) AS i;
    ELSE
        row_name := key_row ->> 'id';
    END IF;

    INSERT INTO audit_log (table_name, row_id, action, changed_by, changed_fields)
    VALUES (TG_TABLE_NAME,
            row_name,
            TG_OP,
            NULLIF(current_setting('app.current_user_id', true), ''),
            CASE TG_OP WHEN 'INSERT' THEN new_row WHEN 'DELETE' THEN old_row ELSE diff END);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_track_labels ON track_labels;
CREATE TRIGGER trg_audit_track_labels AFTER INSERT OR UPDATE OR DELETE ON track_labels
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('analysis_id', 'track_id');

DROP TRIGGER IF EXISTS trg_audit_track_links ON track_links;
CREATE TRIGGER trg_audit_track_links AFTER INSERT OR UPDATE OR DELETE ON track_links
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('analysis_id', 'from_track');

-- The suggestions themselves are written by the analysis; only a person dismissing one is news.
DROP TRIGGER IF EXISTS trg_audit_track_role_suggestions ON track_role_suggestions;
CREATE TRIGGER trg_audit_track_role_suggestions AFTER UPDATE OF dismissed_at ON track_role_suggestions
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('analysis_id', 'track_id');

COMMENT ON COLUMN audit_log.row_id IS 'Fila modificada: su id, o sus columnas clave unidas por "/" (análisis/trayectoria).';
COMMENT ON FUNCTION audit_row_change() IS
    'Trigger de auditoría: escribe en audit_log la fila nueva, la borrada o solo las columnas que cambiaron (sin contraseñas ni documentos grandes). La fila se nombra por su id o por las columnas que se le pasan al trigger.';
