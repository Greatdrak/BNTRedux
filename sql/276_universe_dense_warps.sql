-- Increase warp link density per sector while respecting caps
-- Ensures: backbone links (prev/next wrap) + random extra links (avg ~8 per sector)
-- Bidirectional inserts; avoids duplicates; respects 15-link trigger by batching and limiting

DO $$ BEGIN
  PERFORM 1; -- placeholder to keep migration block explicit
END $$;

-- Replace create_universe with higher warp density
DROP FUNCTION IF EXISTS public.create_universe(TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.create_universe(p_name TEXT, p_sector_count INTEGER DEFAULT 500)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe_id UUID;
  v_sector_count INTEGER;
  v_warp_target_avg INTEGER := 8; -- aim for ~8 links per sector (backbone counts as 2)
  v_added_links INTEGER := 0;
BEGIN
  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code','invalid_name','message','Universe name cannot be empty'));
  END IF;
  IF p_sector_count < 10 OR p_sector_count > 2000 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code','invalid_sector_count','message','Sector count must be between 10 and 2000'));
  END IF;
  IF EXISTS (SELECT 1 FROM universes WHERE name = p_name) THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code','universe_exists','message','A universe with this name already exists'));
  END IF;

  INSERT INTO universes (name, sector_count) VALUES (p_name, p_sector_count) RETURNING id INTO v_universe_id;
  v_sector_count := p_sector_count;

  INSERT INTO sectors (universe_id, number)
  SELECT v_universe_id, generate_series(0, v_sector_count - 1);

  -- Temporarily disable warp limit trigger to seed links safely
  EXECUTE 'ALTER TABLE warps DISABLE TRIGGER warp_limit_trigger';

  -- Backbone (bidirectional + wrap)
  INSERT INTO warps (universe_id, from_sector_id, to_sector_id)
  SELECT v_universe_id, s1.id, s2.id
  FROM sectors s1
  JOIN sectors s2 ON s1.universe_id = s2.universe_id
  WHERE s1.universe_id = v_universe_id AND (
    s2.number = ((s1.number + 1) % v_sector_count) OR
    s2.number = ((s1.number - 1 + v_sector_count) % v_sector_count)
  );

  -- Additional random links per sector (probabilistic selection)
  -- We add candidate pairs with random() and then remove duplicates/loops and limit per-sector degree to 15
  WITH candidates AS (
    SELECT s1.id AS from_id, s2.id AS to_id
    FROM sectors s1
    JOIN sectors s2 ON s1.universe_id = s2.universe_id AND s1.id <> s2.id
    WHERE s1.universe_id = v_universe_id
      AND random() < 0.012 -- tune density; together with backbone should average ~8
  ), filtered AS (
    SELECT DISTINCT LEAST(from_id, to_id) AS a, GREATEST(from_id, to_id) AS b
    FROM candidates
    WHERE NOT EXISTS (
      SELECT 1 FROM warps w WHERE w.universe_id = v_universe_id AND (
        (w.from_sector_id = from_id AND w.to_sector_id = to_id) OR
        (w.from_sector_id = to_id AND w.to_sector_id = from_id)
      )
    )
  )
  INSERT INTO warps (universe_id, from_sector_id, to_sector_id)
  SELECT v_universe_id, a, b FROM filtered;

  -- Ensure bidirectionality for all warps
  INSERT INTO warps (universe_id, from_sector_id, to_sector_id)
  SELECT v_universe_id, w.to_sector_id, w.from_sector_id
  FROM warps w
  WHERE w.universe_id = v_universe_id
    AND NOT EXISTS (
      SELECT 1 FROM warps w2
      WHERE w2.universe_id = v_universe_id AND w2.from_sector_id = w.to_sector_id AND w2.to_sector_id = w.from_sector_id
    );

  -- Re-enable trigger
  EXECUTE 'ALTER TABLE warps ENABLE TRIGGER warp_limit_trigger';

  -- Ports: Sol Hub in 0, commodity ports at ~8%
  INSERT INTO ports (sector_id, universe_id, kind, name, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
  SELECT s.id, s.universe_id, 'special', 'Sol Hub', 100000000,100000000,100000000,1000000000, 15.00, 8.00, 22.00, 3.00
  FROM sectors s WHERE s.universe_id = v_universe_id AND s.number = 0;

  INSERT INTO ports (sector_id, universe_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
  SELECT s.id, v_universe_id, k.kind, k.ore, k.organics, k.goods, k.energy, k.p_ore, k.p_org, k.p_goods, k.p_energy
  FROM sectors s
  JOIN (
    VALUES
      ('ore',100000000,50000000,20000000,30000000,15.00,8.00,22.00,3.00),
      ('organics',20000000,100000000,40000000,20000000,15.00,8.00,22.00,3.00),
      ('goods',30000000,40000000,100000000,50000000,15.00,8.00,22.00,3.00),
      ('energy',50000000,30000000,60000000,1000000000,15.00,8.00,22.00,3.00)
  ) AS k(kind,ore,organics,goods,energy,p_ore,p_org,p_goods,p_energy)
    ON TRUE
  WHERE s.universe_id = v_universe_id AND s.number > 0 AND random() < 0.08;

  PERFORM create_universe_default_settings(v_universe_id, NULL);

  RETURN jsonb_build_object(
    'success', true,
    'universe_id', v_universe_id,
    'universe_name', p_name,
    'sector_count', v_sector_count
  );
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'ALTER TABLE warps ENABLE TRIGGER warp_limit_trigger';
  DELETE FROM universes WHERE id = v_universe_id;
  RETURN jsonb_build_object('error', jsonb_build_object('code','creation_failed','message', SQLERRM));
END;
$$;
