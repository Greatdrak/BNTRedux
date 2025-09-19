-- Update create_universe function to use correct base stock amounts
-- Run once in Supabase SQL Editor

-- ============================================================================
-- 1. UPDATE CREATE_UNIVERSE FUNCTION WITH CORRECT BASE STOCKS
-- ============================================================================

-- Drop existing functions first
DROP FUNCTION IF EXISTS public.create_universe(text, numeric, numeric, integer);
DROP FUNCTION IF EXISTS public.create_universe(text, numeric, numeric, integer, integer);

-- Create updated create_universe function with correct base stocks
CREATE OR REPLACE FUNCTION public.create_universe(
  p_name text DEFAULT 'Alpha',
  p_port_density numeric DEFAULT 0.30,
  p_planet_density numeric DEFAULT 0.25,
  p_sector_count integer DEFAULT 500,
  p_ai_player_count integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe_id UUID;
  v_sector_count INTEGER;
  v_port_count INTEGER;
  v_planet_count INTEGER;
  v_settings_id UUID;
BEGIN
  -- Validate inputs
  IF p_port_density < 0 OR p_port_density > 1 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_density', 'message', 'Port density must be between 0 and 1'));
  END IF;
  
  IF p_planet_density < 0 OR p_planet_density > 1 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_density', 'message', 'Planet density must be between 0 and 1'));
  END IF;
  
  IF p_sector_count < 1 OR p_sector_count > 1000 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_sectors', 'message', 'Sector count must be between 1 and 1000'));
  END IF;

  IF p_ai_player_count < 0 OR p_ai_player_count > 100 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_ai_count', 'message', 'AI player count must be between 0 and 100'));
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
  
  -- Create random warps (additional connections)
  INSERT INTO warps (universe_id, from_sector, to_sector)
  SELECT 
    v_universe_id,
    s1.id as from_sector,
    s2.id as to_sector
  FROM sectors s1, sectors s2
  WHERE s1.universe_id = v_universe_id 
    AND s2.universe_id = v_universe_id
    AND s1.number != s2.number
    AND random() < 0.05 -- 5% chance for random warps
  ON CONFLICT (universe_id, from_sector, to_sector) DO NOTHING;
  
  -- Create Sol Hub (Sector 0) with special port
  INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
  SELECT 
    s.id,
    'special',
    0, 0, 0, 0,
    15.00, 8.00, 22.00, 3.00  -- Updated base prices from live BNT
  FROM sectors s
  WHERE s.universe_id = v_universe_id AND s.number = 0;
  
  -- Create commodity ports with configurable density and CORRECT base stocks
  INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
  SELECT 
    port_data.sector_id,
    port_data.kind,
    -- CORRECTED BASE STOCKS (matching live BNT):
    CASE WHEN port_data.kind = 'ore' THEN 100000000 ELSE 0 END as ore,        -- 100M (not 1B)
    CASE WHEN port_data.kind = 'organics' THEN 100000000 ELSE 0 END as organics, -- 100M (not 1B)
    CASE WHEN port_data.kind = 'goods' THEN 100000000 ELSE 0 END as goods,      -- 100M (not 1B)
    CASE WHEN port_data.kind = 'energy' THEN 1000000000 ELSE 0 END as energy,   -- 1B (correct)
    -- Updated base prices from live BNT screenshots:
    15.00 as price_ore,      -- Updated from 10.00
    8.00 as price_organics,   -- Updated from 12.00
    22.00 as price_goods,     -- Updated from 20.00
    3.00 as price_energy      -- Updated from 6.00
  FROM (
    SELECT 
      s.id as sector_id,
      CASE floor(random() * 4)
        WHEN 0 THEN 'ore'
        WHEN 1 THEN 'organics' 
        WHEN 2 THEN 'goods'
        WHEN 3 THEN 'energy'
      END as kind
    FROM sectors s
    WHERE s.universe_id = v_universe_id 
      AND s.number > 0  -- Exclude sector 0
      AND random() < p_port_density
  ) port_data;
  
  GET DIAGNOSTICS v_port_count = ROW_COUNT;
  
  -- Create planets with configurable density
  INSERT INTO planets (sector_id, name, owner_player_id)
  SELECT 
    s.id,
    'Planet ' || (ROW_NUMBER() OVER (ORDER BY s.id)),
    NULL
  FROM sectors s
  WHERE s.universe_id = v_universe_id 
    AND s.number > 0
    AND random() < p_planet_density;
  
  GET DIAGNOSTICS v_planet_count = ROW_COUNT;
  
  -- Create default universe settings
  SELECT public.create_universe_default_settings(v_universe_id, NULL) INTO v_settings_id;
  
  -- Create AI players if requested
  IF p_ai_player_count > 0 THEN
    -- TODO: Implement AI player creation
    -- This would create AI players with ships in random sectors
  END IF;
  
  -- Return success with statistics
  RETURN jsonb_build_object(
    'ok', true,
    'universe_id', v_universe_id,
    'name', p_name,
    'sectors', v_sector_count + 1, -- +1 for sector 0
    'ports', v_port_count + 1, -- +1 for Sol Hub special port
    'planets', v_planet_count,
    'settings_id', v_settings_id,
    'settings', jsonb_build_object(
      'port_density', p_port_density,
      'planet_density', p_planet_density,
      'sector_count', p_sector_count,
      'ai_player_count', p_ai_player_count
    )
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.create_universe(text, numeric, numeric, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_universe(text, numeric, numeric, integer, integer) TO service_role;

-- ============================================================================
-- 2. VERIFICATION QUERIES
-- ============================================================================

-- Test the updated function (commented out - uncomment to test)
/*
SELECT public.create_universe(
  'Test Universe',
  0.30,
  0.25,
  100,
  0
);
*/

-- Check current port stock distribution
SELECT 
  kind,
  COUNT(*) as port_count,
  AVG(ore) as avg_ore_stock,
  AVG(organics) as avg_organics_stock,
  AVG(goods) as avg_goods_stock,
  AVG(energy) as avg_energy_stock,
  AVG(price_ore) as avg_price_ore,
  AVG(price_organics) as avg_price_organics,
  AVG(price_goods) as avg_price_goods,
  AVG(price_energy) as avg_price_energy
FROM ports 
WHERE kind != 'special'
GROUP BY kind
ORDER BY kind;
