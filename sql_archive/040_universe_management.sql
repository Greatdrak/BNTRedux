-- Universe Management System
-- Consolidated scripts for creating, managing, and destroying universes

-- ============================================================================
-- UNIVERSE CREATION FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION create_universe(
  p_name TEXT DEFAULT 'Alpha',
  p_port_density DECIMAL DEFAULT 0.30,
  p_planet_density DECIMAL DEFAULT 0.25,
  p_sector_count INTEGER DEFAULT 500,
  p_ai_player_count INTEGER DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe_id UUID;
  v_sector_count INTEGER;
  v_port_count INTEGER;
  v_planet_count INTEGER;
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
  
  -- Create random warps (additional connections) - capped at 10 total warps
  -- NOTE: Future warp editor will allow players to add up to 15 total warps
  WITH random_warp_candidates AS (
    SELECT 
      v_universe_id as universe_id,
      s1.id as from_sector,
      s2.id as to_sector,
      ROW_NUMBER() OVER (ORDER BY random()) as rn
    FROM sectors s1, sectors s2
    WHERE s1.universe_id = v_universe_id 
      AND s2.universe_id = v_universe_id
      AND s1.number != s2.number
      AND random() < 0.05 -- 5% chance for random warps
  ),
  current_warp_count AS (
    SELECT COUNT(*) as count
    FROM warps w 
    WHERE w.universe_id = v_universe_id
  )
  INSERT INTO warps (universe_id, from_sector, to_sector)
  SELECT 
    universe_id,
    from_sector,
    to_sector
  FROM random_warp_candidates
  WHERE rn <= GREATEST(0, 10 - (SELECT count FROM current_warp_count))
  ON CONFLICT (universe_id, from_sector, to_sector) DO NOTHING;
  
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
    CASE WHEN port_data.kind = 'ore' THEN 1000000000 ELSE 0 END as ore,
    CASE WHEN port_data.kind = 'organics' THEN 1000000000 ELSE 0 END as organics,
    CASE WHEN port_data.kind = 'goods' THEN 1000000000 ELSE 0 END as goods,
    CASE WHEN port_data.kind = 'energy' THEN 1000000000 ELSE 0 END as energy,
    10.00 as price_ore,
    12.00 as price_organics,
    20.00 as price_goods,
    6.00 as price_energy
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
  
  -- Create AI players if requested
  IF p_ai_player_count > 0 THEN
    INSERT INTO ai_players (universe_id, name, ai_type, economic_score, territorial_score, military_score, exploration_score, total_score)
    SELECT 
      v_universe_id,
      CASE 
        WHEN ai_type = 'trader' THEN 'Trader_AI_' || generate_series(1, p_ai_player_count / 4)
        WHEN ai_type = 'explorer' THEN 'Explorer_AI_' || generate_series(1, p_ai_player_count / 4)
        WHEN ai_type = 'military' THEN 'Military_AI_' || generate_series(1, p_ai_player_count / 4)
        ELSE 'Balanced_AI_' || generate_series(1, p_ai_player_count / 4)
      END,
      ai_type,
      CASE ai_type
        WHEN 'trader' THEN 5000 + (random() * 2000)::INTEGER
        WHEN 'explorer' THEN 1000 + (random() * 1000)::INTEGER
        WHEN 'military' THEN 2000 + (random() * 1500)::INTEGER
        ELSE 3000 + (random() * 1500)::INTEGER
      END,
      CASE ai_type
        WHEN 'trader' THEN 1000 + (random() * 500)::INTEGER
        WHEN 'explorer' THEN 2000 + (random() * 1000)::INTEGER
        WHEN 'military' THEN 3000 + (random() * 1500)::INTEGER
        ELSE 2000 + (random() * 1000)::INTEGER
      END,
      CASE ai_type
        WHEN 'trader' THEN 500 + (random() * 500)::INTEGER
        WHEN 'explorer' THEN 1000 + (random() * 500)::INTEGER
        WHEN 'military' THEN 2000 + (random() * 1000)::INTEGER
        ELSE 1000 + (random() * 750)::INTEGER
      END,
      CASE ai_type
        WHEN 'trader' THEN 500 + (random() * 500)::INTEGER
        WHEN 'explorer' THEN 2000 + (random() * 1000)::INTEGER
        WHEN 'military' THEN 1000 + (random() * 500)::INTEGER
        ELSE 1500 + (random() * 750)::INTEGER
      END,
      0 -- total_score will be calculated by ranking system
    FROM (
      SELECT 'trader' as ai_type
      UNION ALL SELECT 'explorer'
      UNION ALL SELECT 'military'
      UNION ALL SELECT 'balanced'
    ) ai_types
    CROSS JOIN generate_series(1, GREATEST(1, p_ai_player_count / 4)) as ai_count;
  END IF;
  
  -- Return success with statistics
  RETURN jsonb_build_object(
    'ok', true,
    'universe_id', v_universe_id,
    'name', p_name,
    'sectors', v_sector_count + 1, -- +1 for sector 0
    'ports', v_port_count + 1, -- +1 for Sol Hub special port
    'planets', v_planet_count,
    'ai_players', p_ai_player_count,
    'settings', jsonb_build_object(
      'port_density', p_port_density,
      'planet_density', p_planet_density,
      'sector_count', p_sector_count,
      'ai_player_count', p_ai_player_count
    )
  );
END;
$$;

-- ============================================================================
-- UNIVERSE DESTRUCTION FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION destroy_universe(p_universe_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe_name TEXT;
  v_player_count INTEGER;
  v_ship_count INTEGER;
BEGIN
  -- Get universe name for logging
  SELECT name INTO v_universe_name FROM universes WHERE id = p_universe_id;
  
  IF v_universe_name IS NULL THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_not_found', 'message', 'Universe not found'));
  END IF;
  
  -- Count affected entities
  SELECT COUNT(*) INTO v_player_count FROM players WHERE universe_id = p_universe_id;
  SELECT COUNT(*) INTO v_ship_count FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  
  -- Delete all data in dependency order
  DELETE FROM trades WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  DELETE FROM combats WHERE attacker_id IN (SELECT id FROM players WHERE universe_id = p_universe_id) 
    OR defender_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  DELETE FROM visited WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  DELETE FROM scans WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  DELETE FROM favorites WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  DELETE FROM planets WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  DELETE FROM ports WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  DELETE FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  DELETE FROM inventories WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  DELETE FROM players WHERE universe_id = p_universe_id;
  DELETE FROM warps WHERE universe_id = p_universe_id;
  DELETE FROM sectors WHERE universe_id = p_universe_id;
  DELETE FROM universes WHERE id = p_universe_id;
  
  -- Return success with statistics
  RETURN jsonb_build_object(
    'ok', true,
    'universe_name', v_universe_name,
    'players_deleted', v_player_count,
    'ships_deleted', v_ship_count,
    'message', 'Universe destroyed successfully'
  );
END;
$$;

-- ============================================================================
-- UNIVERSE LIST FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION list_universes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb := '[]'::jsonb;
  v_universe record;
  v_sector_count INTEGER;
  v_port_count INTEGER;
  v_planet_count INTEGER;
  v_player_count INTEGER;
BEGIN
  FOR v_universe IN 
    SELECT id, name, created_at 
    FROM universes 
    ORDER BY created_at DESC
  LOOP
    -- Count sectors
    SELECT COUNT(*) INTO v_sector_count FROM sectors WHERE universe_id = v_universe.id;
    
    -- Count ports
    SELECT COUNT(*) INTO v_port_count 
    FROM ports p 
    JOIN sectors s ON p.sector_id = s.id 
    WHERE s.universe_id = v_universe.id;
    
    -- Count planets
    SELECT COUNT(*) INTO v_planet_count 
    FROM planets pl 
    JOIN sectors s ON pl.sector_id = s.id 
    WHERE s.universe_id = v_universe.id;
    
    -- Count players
    SELECT COUNT(*) INTO v_player_count FROM players WHERE universe_id = v_universe.id;
    
    v_result := v_result || jsonb_build_object(
      'id', v_universe.id,
      'name', v_universe.name,
      'created_at', v_universe.created_at,
      'sector_count', v_sector_count,
      'port_count', v_port_count,
      'planet_count', v_planet_count,
      'player_count', v_player_count
    );
  END LOOP;
  
  RETURN jsonb_build_object('ok', true, 'universes', v_result);
END;
$$;
