-- Removes everything sql/seed_demo.sql created (and anything the app added to the demo team).
-- Players are deleted first because deleting a team only unlinks its players (ON DELETE SET NULL);
-- deleting the team then removes its matches, videos, analyses, plays, reports and notifications.

BEGIN;
DELETE FROM players WHERE team_id = 'demo-team' OR id LIKE 'demo-player-%';
DELETE FROM teams WHERE id = 'demo-team';
DELETE FROM users WHERE id IN ('demo-user-coach', 'demo-user-analyst');
COMMIT;
