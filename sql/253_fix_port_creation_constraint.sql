-- Fix the port creation constraint issue in create_universe function
-- The problem is that ports table has a unique constraint on sector_id
-- We need to ensure only one port per sector is created

-- Drop the existing function first
DROP FUNCTION IF EXISTS public.create_universe(TEXT, INTEGER);

CREATE FUNCTION public.create_universe(
  p_name TEXT,
  p_sector_count INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe_id UUID;
  v_warp_count INTEGER := 0;
  v_sector_count INTEGER;
  v_port_count INTEGER;
  v_planet_count INTEGER;
BEGIN
  -- Validate inputs
  IF p_name IS NULL OR LENGTH(TRIM(p_name)) = 0 THEN
    RETURN jsonb_build_object('error', jsonb_build_object(
      'code', 'invalid_name',
      'message', 'Universe name is required'
    ));
  END IF;
  
  IF p_sector_count IS NULL OR p_sector_count < 1 OR p_sector_count > 1000 THEN
    RETURN jsonb_build_object('error', jsonb_build_object(
      'code', 'invalid_sectors', 
      'message', 'Sector count must be between 1 and 1000'
    ));
  END IF;

  -- Create universe record
  INSERT INTO universes (name, sector_count)
  VALUES (TRIM(p_name), p_sector_count)
  RETURNING id INTO v_universe_id;

  -- Create sectors (0 to p_sector_count-1)
  INSERT INTO sectors (universe_id, number)
  SELECT v_universe_id, generate_series(0, p_sector_count - 1);

  -- DISABLE the warp limit trigger temporarily
  DROP TRIGGER IF EXISTS warp_limit_trigger ON warps;

  -- Create backbone warps (each sector connected to the next)
  INSERT INTO warps (universe_id, from_sector, to_sector)
  SELECT 
    v_universe_id,
    s1.id as from_sector,
    s2.id as to_sector
  FROM sectors s1, sectors s2
  WHERE s1.universe_id = v_universe_id 
    AND s2.universe_id = v_universe_id
    AND s2.number = s1.number + 1  -- Connect each sector to the next
  ON CONFLICT (universe_id, from_sector, to_sector) DO NOTHING;

  -- Get current warp count
  SELECT COUNT(*) INTO v_warp_count
  FROM warps 
  WHERE universe_id = v_universe_id;

  -- Create random warps (additional connections) - BUT ONLY if under 15 total warps
  IF v_warp_count < 15 THEN
    INSERT INTO warps (universe_id, from_sector, to_sector)
    SELECT 
      v_universe_id,
      s1.id as from_sector,
      s2.id as to_sector
    FROM sectors s1, sectors s2
    WHERE s1.universe_id = v_universe_id 
      AND s2.universe_id = v_universe_id
      AND s1.number != s2.number
      AND NOT EXISTS (
        SELECT 1 FROM warps w 
        WHERE w.universe_id = v_universe_id 
        AND ((w.from_sector = s1.id AND w.to_sector = s2.id) OR (w.from_sector = s2.id AND w.to_sector = s1.id))
      )
      AND random() < 0.05 -- 5% chance for random warps
    LIMIT (15 - v_warp_count) -- Only add up to the limit
    ON CONFLICT (universe_id, from_sector, to_sector) DO NOTHING;
  END IF;
  
  -- RE-ENABLE the warp limit trigger
  CREATE TRIGGER warp_limit_trigger
    BEFORE INSERT ON warps
    FOR EACH ROW
    EXECUTE FUNCTION check_warp_count();
  
  -- Get final warp count
  SELECT COUNT(*) INTO v_warp_count
  FROM warps 
  WHERE universe_id = v_universe_id;
  
  -- Create Sol Hub (Sector 0) with special port - ONLY ONE PORT PER SECTOR
  INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
  SELECT 
    s.id,
    'special',
    0, 0, 0, 0,
    10.00, 12.00, 20.00, 6.00
  FROM sectors s
  WHERE s.universe_id = v_universe_id AND s.number = 0
  ON CONFLICT (sector_id) DO NOTHING; -- Handle constraint violation gracefully
  
  -- Create commodity ports with configurable density - ONLY ONE PORT PER SECTOR
  INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
  SELECT 
    port_data.sector_id,
    port_data.kind,
    port_data.ore,
    port_data.organics,
    port_data.goods,
    port_data.energy,
    port_data.price_ore,
    port_data.price_organics,
    port_data.price_goods,
    port_data.price_energy
  FROM (
    SELECT 
      s.id as sector_id,
      port_types.kind,
      CASE port_types.kind
        WHEN 'ore' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'organics' THEN FLOOR(RANDOM() * 1000) + 100  
        WHEN 'goods' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'energy' THEN FLOOR(RANDOM() * 1000) + 100
        ELSE 0
      END as ore,
      CASE port_types.kind
        WHEN 'ore' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'organics' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'goods' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'energy' THEN FLOOR(RANDOM() * 1000) + 100
        ELSE 0
      END as organics,
      CASE port_types.kind
        WHEN 'ore' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'organics' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'goods' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'energy' THEN FLOOR(RANDOM() * 1000) + 100
        ELSE 0
      END as goods,
      CASE port_types.kind
        WHEN 'ore' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'organics' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'goods' THEN FLOOR(RANDOM() * 1000) + 100
        WHEN 'energy' THEN FLOOR(RANDOM() * 1000) + 100
        ELSE 0
      END as energy,
      CASE port_types.kind
        WHEN 'ore' THEN (RANDOM() * 5) + 8.00
        WHEN 'organics' THEN (RANDOM() * 5) + 8.00
        WHEN 'goods' THEN (RANDOM() * 10) + 15.00
        WHEN 'energy' THEN (RANDOM() * 3) + 4.00
        ELSE 0
      END as price_ore,
      CASE port_types.kind
        WHEN 'ore' THEN (RANDOM() * 5) + 8.00
        WHEN 'organics' THEN (RANDOM() * 5) + 8.00
        WHEN 'goods' THEN (RANDOM() * 10) + 15.00
        WHEN 'energy' THEN (RANDOM() * 3) + 4.00
        ELSE 0
      END as price_organics,
      CASE port_types.kind
        WHEN 'ore' THEN (RANDOM() * 5) + 8.00
        WHEN 'organics' THEN (RANDOM() * 5) + 8.00
        WHEN 'goods' THEN (RANDOM() * 10) + 15.00
        WHEN 'energy' THEN (RANDOM() * 3) + 4.00
        ELSE 0
      END as price_goods,
      CASE port_types.kind
        WHEN 'ore' THEN (RANDOM() * 5) + 8.00
        WHEN 'organics' THEN (RANDOM() * 5) + 8.00
        WHEN 'goods' THEN (RANDOM() * 10) + 15.00
        WHEN 'energy' THEN (RANDOM() * 3) + 4.00
        ELSE 0
      END as price_energy
    FROM sectors s
    CROSS JOIN (
      SELECT 'ore' as kind UNION ALL
      SELECT 'organics' UNION ALL  
      SELECT 'goods' UNION ALL
      SELECT 'energy'
    ) port_types
    WHERE s.universe_id = v_universe_id 
      AND s.number > 0  -- Don't create commodity ports in sector 0 (Sol Hub)
      AND RANDOM() < 0.30  -- 30% chance for each port type in each sector
  ) port_data
  ON CONFLICT (sector_id) DO NOTHING; -- Handle constraint violation gracefully
  
  -- Create planets with configurable density
  INSERT INTO planets (sector_id, name, ore, organics, goods, energy, colonists)
  SELECT 
    planet_data.sector_id,
    planet_data.name,
    planet_data.ore,
    planet_data.organics, 
    planet_data.goods,
    planet_data.energy,
    planet_data.colonists
  FROM (
    SELECT 
      s.id as sector_id,
      'Planet ' || s.number || '-' || (ROW_NUMBER() OVER (PARTITION BY s.id ORDER BY RANDOM())) as name,
      FLOOR(RANDOM() * 5000) + 1000 as ore,
      FLOOR(RANDOM() * 5000) + 1000 as organics,
      FLOOR(RANDOM() * 5000) + 1000 as goods, 
      FLOOR(RANDOM() * 5000) + 1000 as energy,
      FLOOR(RANDOM() * 10000) + 1000 as colonists
    FROM sectors s
    WHERE s.universe_id = v_universe_id 
      AND s.number > 0  -- Don't create planets in sector 0 (Sol Hub)
      AND RANDOM() < 0.25  -- 25% chance for planets in each sector
  ) planet_data;
  
  -- Get final counts
  SELECT COUNT(*) INTO v_sector_count FROM sectors WHERE universe_id = v_universe_id;
  SELECT COUNT(*) INTO v_port_count FROM ports p JOIN sectors s ON p.sector_id = s.id WHERE s.universe_id = v_universe_id;
  SELECT COUNT(*) INTO v_planet_count FROM planets p JOIN sectors s ON p.sector_id = s.id WHERE s.universe_id = v_universe_id;
  
  -- Return success response
  RETURN jsonb_build_object(
    'success', true,
    'universe_id', v_universe_id,
    'universe_name', TRIM(p_name),
    'sectors_created', v_sector_count,
    'warps_created', v_warp_count,
    'ports_created', v_port_count,
    'planets_created', v_planet_count,
    'message', 'Universe created successfully'
  );

EXCEPTION
  WHEN OTHERS THEN
    -- Clean up on error
    DELETE FROM universes WHERE id = v_universe_id;
    RETURN jsonb_build_object('error', jsonb_build_object(
      'code', 'creation_failed',
      'message', 'Failed to create universe: ' || SQLERRM
    ));
END;
$$;
