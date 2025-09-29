-- Migration: 247_fix_universe_creation_warp_limit.sql
-- Fix the create_universe function to respect the 15 warp limit

CREATE OR REPLACE FUNCTION public.create_universe(p_name TEXT, p_sector_count INTEGER DEFAULT 500)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe_id UUID;
  v_universe_name TEXT;
  v_sector_count INTEGER;
  v_port_count INTEGER;
  v_warp_count INTEGER;
BEGIN
  -- Validate inputs
  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_name', 'message', 'Universe name cannot be empty'));
  END IF;

  IF p_sector_count < 10 OR p_sector_count > 2000 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_sector_count', 'message', 'Sector count must be between 10 and 2000'));
  END IF;

  -- Check if universe with this name already exists
  IF EXISTS (SELECT 1 FROM universes WHERE name = p_name) THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_exists', 'message', 'A universe with this name already exists'));
  END IF;

  -- Create universe
  INSERT INTO universes (name, sector_count) VALUES (p_name, p_sector_count) RETURNING id INTO v_universe_id;
  
  -- Create sectors (0 to p_sector_count)
  INSERT INTO sectors (universe_id, number)
  SELECT v_universe_id, generate_series(0, p_sector_count);
  
  GET DIAGNOSTICS v_sector_count = ROW_COUNT;
  
  -- Create backbone warps (0↔1↔2↔...↔p_sector_count) - bidirectional
  -- This is ESSENTIAL - every sector must connect to the next
  INSERT INTO warps (universe_id, from_sector, to_sector)
  SELECT 
    v_universe_id,
    s1.id as from_sector,
    s2.id as to_sector
  FROM sectors s1, sectors s2
  WHERE s1.universe_id = v_universe_id 
    AND s2.universe_id = v_universe_id
    AND s1.number = s2.number - 1
  UNION ALL
  SELECT 
    v_universe_id,
    s2.id as from_sector,
    s1.id as to_sector
  FROM sectors s1, sectors s2
  WHERE s1.universe_id = v_universe_id 
    AND s2.universe_id = v_universe_id
    AND s1.number = s2.number - 1
  ON CONFLICT (universe_id, from_sector, to_sector) DO NOTHING;
  
  -- Create random warps (additional connections) - BUT ONLY if under 15 total warps
  -- Check current warp count first
  SELECT COUNT(*) INTO v_warp_count
  FROM warps 
  WHERE universe_id = v_universe_id;
  
  -- Only add random warps if we're under the limit
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
  
  -- Get final warp count
  SELECT COUNT(*) INTO v_warp_count
  FROM warps 
  WHERE universe_id = v_universe_id;
  
  -- Create Sol Hub (Sector 0) with special port
  INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
  SELECT 
    s.id,
    'special',
    0, 0, 0, 0,
    10.00, 12.00, 20.00, 6.00
  FROM sectors s
  WHERE s.universe_id = v_universe_id AND s.number = 0;
  
  -- Create commodity ports with configurable density
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
      port_types.ore,
      port_types.organics,
      port_types.goods,
      port_types.energy,
      port_types.price_ore,
      port_types.price_organics,
      port_types.price_goods,
      port_types.price_energy
    FROM sectors s
    CROSS JOIN (
      VALUES 
        ('ore', 1000, 500, 200, 300, 8.00, 15.00, 30.00, 8.00),
        ('organics', 200, 1000, 400, 200, 12.00, 10.00, 35.00, 10.00),
        ('goods', 300, 400, 1000, 500, 20.00, 25.00, 15.00, 12.00),
        ('energy', 500, 300, 600, 1000, 6.00, 8.00, 20.00, 5.00)
    ) AS port_types(kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
    WHERE s.universe_id = v_universe_id 
      AND s.number > 0  -- Don't create commodity ports in sector 0 (Sol Hub)
      AND random() < 0.08  -- 8% chance for commodity ports (reduced from 10%)
  ) AS port_data;
  
  GET DIAGNOSTICS v_port_count = ROW_COUNT;
  
  -- Create universe settings with defaults
  INSERT INTO universe_settings (universe_id)
  VALUES (v_universe_id);
  
  -- Return success with statistics
  RETURN jsonb_build_object(
    'success', true,
    'universe_id', v_universe_id,
    'universe_name', p_name,
    'sector_count', v_sector_count,
    'port_count', v_port_count + 1,  -- +1 for Sol Hub
    'warp_count', v_warp_count,
    'message', 'Universe created successfully'
  );
  
EXCEPTION
  WHEN OTHERS THEN
    -- Clean up on error
    DELETE FROM universes WHERE id = v_universe_id;
    RETURN jsonb_build_object(
      'error', jsonb_build_object(
        'code', 'creation_failed',
        'message', 'Failed to create universe: ' || SQLERRM
      )
    );
END;
$$;
