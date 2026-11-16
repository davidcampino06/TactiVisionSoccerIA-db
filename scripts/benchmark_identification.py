"""Measures the identification queries on a realistic volume of data, without keeping anything.

    DATABASE_URL="postgresql://postgres:postgres@localhost:5432/tactivision_ci" \\
        python scripts/benchmark_identification.py [--analyses 30] [--tracks 100] [--frames 300]

Inside ONE transaction that is rolled back at the end it creates a team with --analyses analysed
clips; each clip has --tracks tracks seen in --frames frames (about 100 detections per track, what
a 10-minute clip analysed every 3 frames gives), a photo per track, links between consecutive
tracks (half accepted) and a referee kit. Then it runs, with EXPLAIN ANALYZE, the queries the app
and the reports make for ONE clip, and prints how long each took and whether it used an index.

Use a scratch database: it refuses a URL that points to Neon. Nothing is left behind.
"""

from __future__ import annotations

import argparse
import os
import sys

import psycopg2

QUERIES = {
    "tracks of a clip (GET /analyses/{id}/tracks)": """
        SELECT track_id, count(*), min(frame_number), max(frame_number), avg(confidence),
               max(player_id), min(timestamp), max(timestamp), max(player_number)
        FROM detections WHERE video_analysis_id = %(analysis)s AND track_id IS NOT NULL
        GROUP BY track_id ORDER BY track_id""",
    "boxes of one second (overlay)": """
        SELECT frame_number, bounding_box_x, bounding_box_y, bounding_box_width, bounding_box_height, track_id
        FROM detections WHERE video_analysis_id = %(analysis)s AND frame_number BETWEEN 150 AND 175""",
    "detections of one track (identity)": """
        SELECT count(*) FROM detections WHERE video_analysis_id = %(analysis)s AND track_id = 42""",
    "links of a clip": """
        SELECT * FROM track_links WHERE analysis_id = %(analysis)s ORDER BY confidence DESC""",
    "v_track_identities of a clip": """
        SELECT * FROM v_track_identities WHERE analysis_id = %(analysis)s""",
    "v_track_link_review of a clip": """
        SELECT * FROM v_track_link_review WHERE analysis_id = %(analysis)s""",
    "v_identification_progress of a clip": """
        SELECT * FROM v_identification_progress WHERE analysis_id = %(analysis)s""",
}

SEED = """
INSERT INTO users (id, first_name, last_name, email, password_hash, role)
VALUES ('bench-coach', 'Banco', 'Prueba', 'bench@club.com', '$2b$12$' || repeat('a', 53), 'COACH');
INSERT INTO teams (id, coach_id, name, invitation_code) VALUES ('bench-team', 'bench-coach', 'Banco', 'BENCH-1');
INSERT INTO matches (id, team_id, opponent, match_date, status) VALUES ('bench-match', 'bench-team', 'Rival', '2026-11-01', 'PLAYED');
INSERT INTO videos (id, match_id, file_name, file_path, format, file_size)
SELECT 'bench-video-' || a, 'bench-match', 'clip' || a || '.mp4', 'uploads/clip' || a || '.mp4', 'MP4', 1000
FROM generate_series(1, %(analyses)s) a;
INSERT INTO video_analyses (id, video_id, status)
SELECT 'bench-analysis-' || a, 'bench-video-' || a, 'COMPLETED' FROM generate_series(1, %(analyses)s) a;
-- Track t is seen from frame 3*t, every 3 frames, about 100 times (a real clip: many short tracks).
INSERT INTO detections (id, video_analysis_id, frame_number, timestamp, object_type, confidence, bounding_box_x,
                        bounding_box_y, bounding_box_width, bounding_box_height, track_id)
SELECT 'bench-d-' || a || '-' || t || '-' || f, 'bench-analysis-' || a, f, f / 25.0, 'PLAYER', 0.6,
       (t * 37) %% 1800, 300, 30, 80, t
FROM generate_series(1, %(analyses)s) a, generate_series(1, %(tracks)s) t,
     generate_series(0, %(frames)s, 3) f
WHERE f BETWEEN (t * 3) %% %(frames)s AND (t * 3) %% %(frames)s + 300;
INSERT INTO track_snapshots (analysis_id, track_id, frame_number, timestamp, confidence, width, height, image)
SELECT 'bench-analysis-' || a, t, 0, 0, 0.9, 30, 80, decode('ffd8ffe0', 'hex')
FROM generate_series(1, %(analyses)s) a, generate_series(1, %(tracks)s) t;
INSERT INTO track_links (analysis_id, from_track, to_track, from_last_frame, to_first_frame, gap_seconds,
                         distance_heights, confidence, status, decided_at)
SELECT 'bench-analysis-' || a, t, t + 1, 3 * t, 3 * t + 9, 0.36, 0.2, 0.8,
       CASE WHEN t %% 2 = 0 THEN 'ACCEPTED' ELSE 'SUGGESTED' END, CASE WHEN t %% 2 = 0 THEN now() END
FROM generate_series(1, %(analyses)s) a, generate_series(1, %(tracks)s - 1, 3) t;
INSERT INTO track_role_suggestions (analysis_id, track_id, suggestion, kit_group, kit_color, kit_tracks, confidence, reason)
SELECT 'bench-analysis-' || a, t, 'GOALKEEPER_OR_REFEREE', 1, '#3bb3c2', 4, 0.5, 'Camiseta #3bb3c2, de ningún equipo'
FROM generate_series(1, %(analyses)s) a, generate_series(%(tracks)s - 3, %(tracks)s) t;
ANALYZE detections; ANALYZE track_links; ANALYZE track_role_suggestions; ANALYZE track_snapshots;
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--analyses", type=int, default=30)
    parser.add_argument("--tracks", type=int, default=100)
    parser.add_argument("--frames", type=int, default=300)
    args = parser.parse_args()
    url = os.getenv("DATABASE_URL")
    if not url:
        print("Set DATABASE_URL to a scratch database first.")
        return 1
    if "neon.tech" in url:
        print("This creates thousands of rows (rolled back at the end): use a scratch database, not Neon.")
        return 1

    connection = psycopg2.connect(url)
    try:
        with connection.cursor() as cursor:
            cursor.execute(SEED, vars(args))
            cursor.execute("SELECT count(*) FROM detections WHERE video_analysis_id LIKE 'bench-%%'")
            print(f"{cursor.fetchone()[0]} detections in {args.analyses} clips of {args.tracks} tracks\n")
            print(f"{'query':45} {'ms':>8}  index")
            for name, query in QUERIES.items():
                cursor.execute("EXPLAIN (ANALYZE, FORMAT JSON) " + query, {"analysis": "bench-analysis-7"})
                plan = cursor.fetchone()[0][0]
                text = str(plan["Plan"])
                index = "yes" if "Index" in text else "NO (sequential scan)" if "Seq Scan" in text else "-"
                print(f"{name:45} {plan['Execution Time']:8.2f}  {index}")
    finally:
        connection.rollback()
        connection.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
