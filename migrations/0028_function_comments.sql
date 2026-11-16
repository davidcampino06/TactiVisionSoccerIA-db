-- 0028 - Describe the database functions (they had no comment).
--
-- The data dictionary now lists the functions of the project (scripts/data_dictionary.py); these
-- comments say what each one does, so the document explains Row-Level Security and the audit log
-- without reading the migrations. Only comments: no behaviour changes. Idempotent.

COMMENT ON FUNCTION app_rls_bypass() IS
    'Verdadero cuando la sesión pidió saltarse RLS (app.bypass_rls = on): solo tareas del sistema, como un análisis en segundo plano.';
COMMENT ON FUNCTION app_current_user() IS
    'Usuario de la sesión (app.current_user_id), que el backend fija en cada petición; NULL si no hay.';
COMMENT ON FUNCTION app_current_role() IS
    'Rol del usuario de la sesión (app.current_role): COACH, ANALYST o ADMINISTRATOR.';
COMMENT ON FUNCTION app_current_team() IS
    'Equipo del usuario de la sesión (app.current_team_id); las políticas RLS comparan cada fila con él.';
COMMENT ON FUNCTION app_can_see_team(VARCHAR) IS
    'Regla central de RLS: verdadero si la fila es del equipo de la sesión o si la sesión es del sistema.';
COMMENT ON FUNCTION audit_row_change() IS
    'Disparador de auditoría: guarda en audit_log quién cambió qué (solo columnas que cambiaron), sin copiar nunca el hash de la contraseña.';
