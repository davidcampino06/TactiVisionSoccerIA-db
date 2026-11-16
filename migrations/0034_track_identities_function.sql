-- 0034 - The chains of linked tracks of ONE clip, without reading the links of every clip.
--
-- v_track_identities (migration 0032) is a recursive view: PostgreSQL cannot push a
-- "WHERE analysis_id = ..." inside the recursion, so asking for one clip builds the chains of all
-- of them and then filters. Measured with scripts/benchmark_identification.py (local PostgreSQL 16):
-- 1.1 ms with 30 clips and 9.1 ms with 300, growing with every clip any team analyses.
--
-- track_identities_of(analysis) does the same walk with the clip fixed in both parts of the
-- recursion, so it uses the keys of track_links and costs the same whatever the number of clips.
-- SECURITY INVOKER and STABLE: Row-Level Security applies as in the view (a team never gets the
-- chains of another team's clip). The view stays for reports over every clip. Idempotent.

CREATE OR REPLACE FUNCTION track_identities_of(p_analysis_id VARCHAR)
    RETURNS TABLE (track_id INTEGER, person_track INTEGER, step INTEGER)
    LANGUAGE sql STABLE SECURITY INVOKER AS $$
    WITH RECURSIVE chain AS (
        SELECT l.from_track AS person_track, l.from_track AS track_id, 0 AS step
        FROM track_links l
        WHERE l.analysis_id = p_analysis_id AND l.status = 'ACCEPTED'
          AND NOT EXISTS (SELECT 1 FROM track_links before
                          WHERE before.analysis_id = p_analysis_id AND before.to_track = l.from_track
                            AND before.status = 'ACCEPTED')
        UNION ALL
        SELECT c.person_track, l.to_track, c.step + 1
        FROM chain c
        JOIN track_links l ON l.analysis_id = p_analysis_id AND l.from_track = c.track_id AND l.status = 'ACCEPTED'
        WHERE c.step < 500  -- the same limit as the view
    )
    SELECT chain.track_id, chain.person_track, chain.step FROM chain ORDER BY chain.person_track, chain.step;
$$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactivision_app') THEN
        GRANT EXECUTE ON FUNCTION track_identities_of(VARCHAR) TO tactivision_app;
    END IF;
END $$;

COMMENT ON FUNCTION track_identities_of(VARCHAR) IS
    'Cadenas de trayectorias unidas por enlaces aceptados de UN análisis (lo mismo que v_track_identities, sin recorrer los demás clips).';
