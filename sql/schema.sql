CREATE TABLE system_status (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL
);

INSERT INTO system_status (name, status)
VALUES ('TactiVision', 'ACTIVE');