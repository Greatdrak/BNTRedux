-- Migration: 277_dense_links_alpha.sql
-- Purpose: Safely add additional bidirectional warp links in the existing universe "Alpha"
--          without exceeding the per-sector link cap. Keeps trigger enabled.

DO $$
DECLARE
  v_universe_id uuid;
  v_target_min integer := 8;     -- desired minimum links per sector (adjust if needed)
  v_max_per_sector integer := 15;-- hard cap per sector
  v_added integer := 0;
  v_attempts integer := 0;
  v_max_attempts integer := 200000;

  v_from uuid;
  v_to   uuid;

  v_col_from text := 'from_sector';
  v_col_to   text := 'to_sector';
BEGIN
  SELECT id INTO v_universe_id FROM universes WHERE name = 'Alpha';
  IF NOT FOUND THEN
    RAISE NOTICE 'Universe "Alpha" not found; skipping dense-link migration.';
    RETURN;
  END IF;

  -- Detect column names for warps table
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='warps' AND column_name='from_sector_id') THEN
    v_col_from := 'from_sector_id';
    v_col_to   := 'to_sector_id';
  END IF;

  -- Snapshot degrees (outgoing link count per sector)
  CREATE TEMP TABLE tmp_deg AS
  SELECT s.id AS sector_id,
         COALESCE((SELECT COUNT(*) FROM warps w
                   WHERE w.universe_id = s.universe_id
                     AND (CASE WHEN v_col_from='from_sector' THEN w.from_sector ELSE w.from_sector_id END) = s.id), 0) AS deg
  FROM sectors s
  WHERE s.universe_id = v_universe_id;

  WHILE v_attempts < v_max_attempts LOOP
    v_attempts := v_attempts + 1;

    -- Sector needing links
    SELECT sector_id INTO v_from
    FROM tmp_deg
    WHERE deg < v_target_min
    ORDER BY deg ASC, random()
    LIMIT 1;

    IF NOT FOUND THEN
      EXIT; -- target achieved
    END IF;

    -- Candidate partner under cap, not self, and not already linked (either direction)
    WITH cand AS (
      SELECT td.sector_id
      FROM tmp_deg td
      WHERE td.sector_id <> v_from
        AND td.deg < v_max_per_sector
        AND NOT EXISTS (
          SELECT 1 FROM warps w
          WHERE w.universe_id = v_universe_id
            AND (
                  (CASE WHEN v_col_from='from_sector' THEN w.from_sector ELSE w.from_sector_id END) = v_from
              AND (CASE WHEN v_col_to  ='to_sector'   THEN w.to_sector   ELSE w.to_sector_id   END) = td.sector_id
                OR
                  (CASE WHEN v_col_from='from_sector' THEN w.from_sector ELSE w.from_sector_id END) = td.sector_id
              AND (CASE WHEN v_col_to  ='to_sector'   THEN w.to_sector   ELSE w.to_sector_id   END) = v_from
                )
        )
      ORDER BY td.deg ASC, random()
      LIMIT 1
    )
    SELECT sector_id INTO v_to FROM cand;

    IF NOT FOUND THEN
      -- mark sector as saturated to avoid spinning
      UPDATE tmp_deg SET deg = v_max_per_sector WHERE sector_id = v_from AND deg < v_target_min;
      CONTINUE;
    END IF;

    -- Respect caps
    IF (SELECT deg FROM tmp_deg WHERE sector_id = v_from) >= v_max_per_sector OR
       (SELECT deg FROM tmp_deg WHERE sector_id = v_to)   >= v_max_per_sector THEN
      CONTINUE;
    END IF;

    -- Insert bidirectional link
    BEGIN
      EXECUTE format('INSERT INTO warps (universe_id, %I, %I) VALUES ($1,$2,$3)', v_col_from, v_col_to)
      USING v_universe_id, v_from, v_to;

      EXECUTE format('INSERT INTO warps (universe_id, %I, %I) VALUES ($1,$2,$3)', v_col_from, v_col_to)
      USING v_universe_id, v_to, v_from;

      UPDATE tmp_deg SET deg = deg + 1 WHERE sector_id IN (v_from, v_to);
      v_added := v_added + 1;
    EXCEPTION WHEN unique_violation OR check_violation THEN
      -- triggered cap or duplicate, skip
      CONTINUE;
    END;
  END LOOP;

  RAISE NOTICE 'Dense-link migration complete for Alpha: % links added (attempts=%).', v_added, v_attempts;
END $$;
