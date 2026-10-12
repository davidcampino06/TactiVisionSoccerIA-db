-- 0005 - Proximity network of each analysis (graph + BFS computed by the AI Service).
-- The AI returns, for the frame with most visible players, the graph of supports between
-- team-mates: nodes, links, groups, isolated players, diameter and BFS hops between players.
-- It is stored as a JSON document (TEXT, like reports.snapshot_data) because it is read whole
-- to draw it and never queried by field. Nullable: older analyses do not have it.
-- Row-Level Security: video_analyses already has its policy (migration 0002). Idempotent.

ALTER TABLE video_analyses ADD COLUMN IF NOT EXISTS proximity_network TEXT;
