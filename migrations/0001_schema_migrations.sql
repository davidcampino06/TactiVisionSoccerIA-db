-- 0001 - Migration history.
-- Records which numbered migrations were already applied (see scripts/apply_migrations.py).

CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(100) PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
