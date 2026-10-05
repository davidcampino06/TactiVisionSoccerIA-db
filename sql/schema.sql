-- TactiVision IA - PostgreSQL schema (idempotent). Changes vs ERD: see README.md

CREATE TABLE IF NOT EXISTS system_status (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL
);

INSERT INTO system_status (name, status)
SELECT 'TactiVision', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM system_status WHERE name = 'TactiVision');

CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(36) PRIMARY KEY,
    first_name VARCHAR(255) NOT NULL,
    last_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(255),
    profile_image_url VARCHAR(255),
    role VARCHAR(20) NOT NULL CHECK (role IN ('ADMINISTRATOR', 'COACH', 'ANALYST')),
    team_id VARCHAR(36),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS teams (
    id VARCHAR(36) PRIMARY KEY,
    coach_id VARCHAR(36) NOT NULL UNIQUE REFERENCES users(id),
    name VARCHAR(255) NOT NULL,
    category VARCHAR(255),
    city VARCHAR(255),
    description VARCHAR(255),
    invitation_code VARCHAR(20) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_users_team') THEN
        ALTER TABLE users
            ADD CONSTRAINT fk_users_team FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS players (
    id VARCHAR(36) PRIMARY KEY,
    team_id VARCHAR(36) REFERENCES teams(id) ON DELETE SET NULL,
    first_name VARCHAR(255) NOT NULL,
    last_name VARCHAR(255) NOT NULL,
    shirt_number INTEGER CHECK (shirt_number BETWEEN 0 AND 99),
    position VARCHAR(255),
    status VARCHAR(255) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS player_team_history (
    id VARCHAR(36) PRIMARY KEY,
    player_id VARCHAR(36) NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    team_id VARCHAR(36) NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_at TIMESTAMP,
    withdrawal_reason VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS matches (
    id VARCHAR(36) PRIMARY KEY,
    team_id VARCHAR(36) NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    opponent VARCHAR(255) NOT NULL,
    is_home BOOLEAN NOT NULL DEFAULT TRUE,
    match_date TIMESTAMP NOT NULL,
    home_score INTEGER CHECK (home_score >= 0),
    away_score INTEGER CHECK (away_score >= 0),
    result VARCHAR(255),
    location VARCHAR(255),
    status VARCHAR(255) NOT NULL DEFAULT 'SCHEDULED'
);

CREATE TABLE IF NOT EXISTS match_events (
    id VARCHAR(36) PRIMARY KEY,
    match_id VARCHAR(36) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    minute INTEGER NOT NULL CHECK (minute >= 0),
    second INTEGER NOT NULL DEFAULT 0 CHECK (second BETWEEN 0 AND 59),
    event_type VARCHAR(255) NOT NULL,
    zone VARCHAR(255),
    source_x DECIMAL(10, 4),
    source_y DECIMAL(10, 4),
    result VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS formations (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description VARCHAR(255),
    player_count INTEGER NOT NULL DEFAULT 11 CHECK (player_count BETWEEN 1 AND 11),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS match_formations (
    id VARCHAR(36) PRIMARY KEY,
    match_id VARCHAR(36) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    formation_id VARCHAR(36) NOT NULL REFERENCES formations(id) ON DELETE CASCADE,
    UNIQUE (match_id, formation_id)
);

CREATE TABLE IF NOT EXISTS tactical_plays (
    id VARCHAR(36) PRIMARY KEY,
    team_id VARCHAR(36) NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(255),
    action_type VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_reusable BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS tactical_play_versions (
    id VARCHAR(36) PRIMARY KEY,
    tactical_play_id VARCHAR(36) NOT NULL REFERENCES tactical_plays(id) ON DELETE CASCADE,
    created_by VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
    version_number INTEGER NOT NULL,
    configuration_data TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_current BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (tactical_play_id, version_number)
);

CREATE TABLE IF NOT EXISTS match_tactical_plays (
    id VARCHAR(36) PRIMARY KEY,
    match_id VARCHAR(36) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    tactical_play_id VARCHAR(36) NOT NULL REFERENCES tactical_plays(id) ON DELETE CASCADE,
    UNIQUE (match_id, tactical_play_id)
);

CREATE TABLE IF NOT EXISTS videos (
    id VARCHAR(36) PRIMARY KEY,
    match_id VARCHAR(36) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(255) NOT NULL,
    format VARCHAR(50) NOT NULL,
    file_size BIGINT NOT NULL CHECK (file_size > 0),
    duration_seconds INTEGER,
    uploaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) NOT NULL DEFAULT 'UPLOADED'
);

CREATE TABLE IF NOT EXISTS video_analyses (
    id VARCHAR(36) PRIMARY KEY,
    video_id VARCHAR(36) NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    analysis_mode VARCHAR(30) NOT NULL DEFAULT 'REAL_VIDEO_ANALYSIS'
        CHECK (analysis_mode IN ('REAL_VIDEO_ANALYSIS', 'SIMULATION_MODE')),
    confidence_threshold DECIMAL(10, 4),
    model_name VARCHAR(100),
    model_version VARCHAR(50),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    warning_message VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS detections (
    id VARCHAR(36) PRIMARY KEY,
    video_analysis_id VARCHAR(36) NOT NULL REFERENCES video_analyses(id) ON DELETE CASCADE,
    player_id VARCHAR(36) REFERENCES players(id) ON DELETE SET NULL,
    frame_number INTEGER NOT NULL,
    timestamp DECIMAL(10, 4) NOT NULL,
    object_type VARCHAR(50) NOT NULL,
    confidence DECIMAL(10, 4) NOT NULL,
    bounding_box_x DECIMAL(10, 4) NOT NULL,
    bounding_box_y DECIMAL(10, 4) NOT NULL,
    bounding_box_width DECIMAL(10, 4) NOT NULL,
    bounding_box_height DECIMAL(10, 4) NOT NULL,
    player_number INTEGER,
    track_id INTEGER
);

CREATE TABLE IF NOT EXISTS tactical_indicators (
    id VARCHAR(36) PRIMARY KEY,
    video_analysis_id VARCHAR(36) NOT NULL REFERENCES video_analyses(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    value DECIMAL(10, 4) NOT NULL,
    unit VARCHAR(50) NOT NULL,
    calculated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    threshold DECIMAL(10, 4)
);

CREATE TABLE IF NOT EXISTS ai_recommendations (
    id VARCHAR(36) PRIMARY KEY,
    match_id VARCHAR(36) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description VARCHAR(255) NOT NULL,
    severity VARCHAR(50) NOT NULL,
    confidence DECIMAL(10, 4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    evidence VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) NOT NULL DEFAULT 'GENERATED'
        CHECK (status IN ('GENERATED', 'REVIEWED', 'CONFIRMED', 'DISMISSED'))
);

CREATE TABLE IF NOT EXISTS recommendation_indicators (
    id VARCHAR(36) PRIMARY KEY,
    recommendation_id VARCHAR(36) NOT NULL REFERENCES ai_recommendations(id) ON DELETE CASCADE,
    indicator_id VARCHAR(36) NOT NULL REFERENCES tactical_indicators(id) ON DELETE CASCADE,
    UNIQUE (recommendation_id, indicator_id)
);

CREATE TABLE IF NOT EXISTS reports (
    id VARCHAR(36) PRIMARY KEY,
    team_id VARCHAR(36) NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    generated_by VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    report_type VARCHAR(50) NOT NULL,
    generated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version INTEGER NOT NULL DEFAULT 1,
    snapshot_data TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_team ON users(team_id);
CREATE INDEX IF NOT EXISTS idx_players_team ON players(team_id);
CREATE INDEX IF NOT EXISTS idx_matches_team_date ON matches(team_id, match_date);
CREATE INDEX IF NOT EXISTS idx_match_events_match ON match_events(match_id);
CREATE INDEX IF NOT EXISTS idx_videos_match ON videos(match_id);
CREATE INDEX IF NOT EXISTS idx_video_analyses_video ON video_analyses(video_id);
CREATE INDEX IF NOT EXISTS idx_detections_analysis_frame ON detections(video_analysis_id, frame_number);
CREATE INDEX IF NOT EXISTS idx_detections_analysis_track ON detections(video_analysis_id, track_id);
CREATE INDEX IF NOT EXISTS idx_indicators_analysis ON tactical_indicators(video_analysis_id);
CREATE INDEX IF NOT EXISTS idx_recommendations_match ON ai_recommendations(match_id);
CREATE INDEX IF NOT EXISTS idx_reports_team ON reports(team_id);