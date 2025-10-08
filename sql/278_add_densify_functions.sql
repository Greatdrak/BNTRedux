-- Migration: 278_add_densify_functions.sql
-- Adds functions to densify warp links in-place with JSON output.

CREATE OR REPLACE FUNCTION public.densify_universe_links(
  p_universe_id uuid,
  p_target_min integer DEFAULT 8,
  p_max_per_sector integer DEFAULT 15,
  p_max_attempts integer DEFAULT 200000
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_added integer := 0;
  v_attempts integer := 0;
  v_sectors_at_target integer := 0;
  v_from uuid;
  v_to   uuid;
BEGIN
  IF p_universe_id IS NULL THEN
    RETURN jsonb_build_object('error','universe_id_required');
  END IF;

  -- Snapshot undirected degree (unique neighbors either direction)
  CREATE TEMP TABLE tmp_deg AS
  SELECT s.id AS sector_id,
         COALESCE(
           (
             SELECT COUNT(*) FROM (
               SELECT DISTINCT CASE WHEN w.from_sector = s.id THEN w.to_sector ELSE w.from_sector END AS nbr
               FROM warps w
               WHERE w.universe_id = s.universe_id
                 AND (w.from_sector = s.id OR w.to_sector = s.id)
             ) q
           ), 0
         ) AS deg
  FROM sectors s
  WHERE s.universe_id = p_universe_id;

  LOOP
    EXIT WHEN v_attempts >= p_max_attempts;
    v_attempts := v_attempts + 1;

    -- pick a sector under target
    SELECT sector_id INTO v_from
    FROM tmp_deg
    WHERE deg < p_target_min
    ORDER BY deg ASC, random()
    LIMIT 1;

    IF NOT FOUND THEN
      EXIT; -- all at/above target
    END IF;

    -- partner under cap and not already linked
    WITH cand AS (
      SELECT td.sector_id
      FROM tmp_deg td
      WHERE td.sector_id <> v_from
        AND td.deg < p_max_per_sector
        AND NOT EXISTS (
          SELECT 1 FROM warps w
          WHERE w.universe_id = p_universe_id
            AND (
                  (w.from_sector = v_from AND w.to_sector = td.sector_id)
               OR (w.from_sector = td.sector_id AND w.to_sector = v_from)
            )
        )
      ORDER BY td.deg ASC, random()
      LIMIT 1
    )
    SELECT sector_id INTO v_to FROM cand;

    IF NOT FOUND THEN
      -- mark saturated to avoid spinning
      UPDATE tmp_deg SET deg = p_max_per_sector WHERE sector_id = v_from AND deg < p_target_min;
      CONTINUE;
    END IF;

    -- caps check
    IF (SELECT deg FROM tmp_deg WHERE sector_id = v_from) >= p_max_per_sector OR
       (SELECT deg FROM tmp_deg WHERE sector_id = v_to)   >= p_max_per_sector THEN
      CONTINUE;
    END IF;

    BEGIN
      INSERT INTO warps (universe_id, from_sector, to_sector) VALUES (p_universe_id, v_from, v_to);
      INSERT INTO warps (universe_id, from_sector, to_sector) VALUES (p_universe_id, v_to, v_from);
      v_added := v_added + 1;
      -- update local undirected degrees by +1 for both endpoints
      UPDATE tmp_deg SET deg = deg + 1 WHERE sector_id IN (v_from, v_to);
    EXCEPTION WHEN unique_violation OR check_violation THEN
      CONTINUE;
    END;
  END LOOP;

  SELECT COUNT(*) INTO v_sectors_at_target FROM tmp_deg WHERE deg >= p_target_min;

  RETURN jsonb_build_object(
    'ok', true,
    'links_added', v_added,
    'attempts', v_attempts,
    'sectors_at_target', v_sectors_at_target
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.densify_universe_links_by_name(
  p_universe_name text,
  p_target_min integer DEFAULT 8,
  p_max_per_sector integer DEFAULT 15,
  p_max_attempts integer DEFAULT 200000
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id FROM universes WHERE name = p_universe_name;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error','universe_not_found','name',p_universe_name);
  END IF;
  RETURN public.densify_universe_links(v_id, p_target_min, p_max_per_sector, p_max_attempts);
END;
$$;
