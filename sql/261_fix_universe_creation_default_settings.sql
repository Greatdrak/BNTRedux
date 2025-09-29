-- Migration: 261_fix_universe_creation_default_settings.sql
-- Fix create_universe function to create proper default universe settings

-- Drop the existing function first
DROP FUNCTION IF EXISTS public.create_universe(TEXT, INTEGER);

-- Recreate create_universe function with proper default settings
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

  -- Create sectors (0 to p_sector_count-1)
  INSERT INTO sectors (universe_id, number)
  SELECT v_universe_id, generate_series(0, p_sector_count - 1);

  -- DISABLE the warp limit trigger temporarily
  DROP TRIGGER IF EXISTS warp_limit_trigger ON warps;

  -- Create backbone warps (each sector connected to the next) - BIDIRECTIONAL
  INSERT INTO warps (universe_id, from_sector, to_sector)
  SELECT v_universe_id, s1.number, s2.number
  FROM sectors s1
  JOIN sectors s2 ON s2.number = s1.number + 1
  WHERE s1.universe_id = v_universe_id AND s2.universe_id = v_universe_id;

  -- Add random warps (more aggressive to create rich connectivity)
  INSERT INTO warps (universe_id, from_sector, to_sector)
  SELECT v_universe_id, s1.number, s2.number
  FROM sectors s1
  CROSS JOIN sectors s2
  WHERE s1.universe_id = v_universe_id 
    AND s2.universe_id = v_universe_id
    AND s1.number != s2.number
    AND s1.number != s2.number - 1  -- Don't duplicate backbone
    AND s1.number != s2.number + 1  -- Don't duplicate backbone
    AND random() < 0.02  -- 2% chance for random warps
  LIMIT (p_sector_count * 2);  -- Cap additional warps

  -- RE-ENABLE the warp limit trigger
  CREATE TRIGGER warp_limit_trigger
    BEFORE INSERT ON warps
    FOR EACH ROW
    EXECUTE FUNCTION check_warp_count();

  -- Count total warps created
  SELECT COUNT(*) INTO v_warp_count FROM warps WHERE universe_id = v_universe_id;

  -- Create Sol Hub (Special Port in sector 0)
  INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
  SELECT s.id, 'special', 0, 0, 0, 0, 0, 0, 0, 0
  FROM sectors s
  WHERE s.universe_id = v_universe_id AND s.number = 0;

  -- Create commodity ports in random sectors (excluding sector 0)
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
  
  -- Create universe settings with proper defaults using the existing function
  PERFORM create_universe_default_settings(v_universe_id, NULL);
  
  -- Return success with statistics
  RETURN jsonb_build_object(
    'success', true,
    'universe_id', v_universe_id,
    'universe_name', p_name,
    'sector_count', v_sector_count,
    'port_count', v_port_count + 1,  -- +1 for Sol Hub
    'warp_count', v_warp_count,
    'message', 'Universe created successfully with default settings'
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
