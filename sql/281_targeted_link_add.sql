-- Migration: 281_targeted_link_add.sql
-- Adds a helper function to add one bidirectional link for a given sector number (by universe name),
-- honoring the per-sector cap and avoiding duplicates. Useful for diagnosing blocked inserts.

CREATE OR REPLACE FUNCTION public.add_one_link_for_sector(
  p_universe_name text,
  p_sector_number integer,
  p_max_per_sector integer DEFAULT 15
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe uuid;
  v_from uuid;
  v_to uuid;
  v_added boolean := false;
BEGIN
  SELECT id INTO v_universe FROM universes WHERE name = p_universe_name;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error','universe_not_found');
  END IF;

  SELECT id INTO v_from FROM sectors WHERE universe_id = v_universe AND number = p_sector_number;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error','sector_not_found');
  END IF;

  -- Find a partner sector under cap, not already linked (either direction)
  WITH deg AS (
    SELECT s.id AS sector_id,
           COALESCE((
             SELECT COUNT(*) FROM (
               SELECT DISTINCT CASE WHEN w.from_sector = s.id THEN w.to_sector ELSE w.from_sector END AS nbr
               FROM warps w
               WHERE w.universe_id = s.universe_id AND (w.from_sector = s.id OR w.to_sector = s.id)
             ) q
           ), 0) AS degree
    FROM sectors s
    WHERE s.universe_id = v_universe
  )
  SELECT d.sector_id INTO v_to
  FROM deg d
  WHERE d.sector_id <> v_from
    AND d.degree < p_max_per_sector
    AND NOT EXISTS (
      SELECT 1 FROM warps w
      WHERE w.universe_id = v_universe
        AND ((w.from_sector = v_from AND w.to_sector = d.sector_id) OR (w.from_sector = d.sector_id AND w.to_sector = v_from))
    )
  ORDER BY d.degree ASC, random()
  LIMIT 1;

  IF v_to IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'message','no_eligible_partner_found');
  END IF;

  BEGIN
    INSERT INTO warps (universe_id, from_sector, to_sector) VALUES (v_universe, v_from, v_to);
    INSERT INTO warps (universe_id, from_sector, to_sector) VALUES (v_universe, v_to, v_from);
    v_added := true;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;

  RETURN jsonb_build_object('ok', v_added, 'from', p_sector_number,
                             'to', (SELECT number FROM sectors WHERE id = v_to));
END;
$$;
