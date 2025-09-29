-- Migration: 243_simple_destroy_universe.sql
-- Create a very simple destroy_universe function that only deletes what definitely exists

CREATE OR REPLACE FUNCTION public.destroy_universe(p_universe_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe_name TEXT;
  v_player_count INTEGER;
  v_ship_count INTEGER;
  v_planet_count INTEGER;
  v_port_count INTEGER;
  v_sector_count INTEGER;
BEGIN
  -- Get universe name for logging
  SELECT name INTO v_universe_name FROM universes WHERE id = p_universe_id;
  
  IF v_universe_name IS NULL THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_not_found', 'message', 'Universe not found'));
  END IF;
  
  -- Count affected entities
  SELECT COUNT(*) INTO v_player_count FROM players WHERE universe_id = p_universe_id;
  SELECT COUNT(*) INTO v_ship_count FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  SELECT COUNT(*) INTO v_planet_count FROM planets WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  SELECT COUNT(*) INTO v_port_count FROM ports WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  SELECT COUNT(*) INTO v_sector_count FROM sectors WHERE universe_id = p_universe_id;
  
  BEGIN
    -- Delete only from tables we know exist and have the right structure
    -- Core game tables first
    
    -- Delete planets (uses sector_id)
    DELETE FROM planets WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    
    -- Delete ports (uses sector_id) 
    DELETE FROM ports WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    
    -- Delete ships (uses player_id)
    DELETE FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
    
    -- Delete players (has universe_id)
    DELETE FROM players WHERE universe_id = p_universe_id;
    
    -- Delete warps (has universe_id)
    DELETE FROM warps WHERE universe_id = p_universe_id;
    
    -- Delete sectors (has universe_id)
    DELETE FROM sectors WHERE universe_id = p_universe_id;
    
    -- Finally, delete the universe itself
    DELETE FROM universes WHERE id = p_universe_id;
    
  EXCEPTION
    WHEN OTHERS THEN
      RETURN jsonb_build_object(
        'error', jsonb_build_object(
          'code', 'destroy_failed',
          'message', 'Failed to destroy universe: ' || SQLERRM
        )
      );
  END;
  
  -- Return success with statistics
  RETURN jsonb_build_object(
    'success', true,
    'universe_name', v_universe_name,
    'universe_id', p_universe_id,
    'statistics', jsonb_build_object(
      'players_deleted', v_player_count,
      'ships_deleted', v_ship_count,
      'planets_deleted', v_planet_count,
      'ports_deleted', v_port_count,
      'sectors_deleted', v_sector_count
    ),
    'message', 'Universe destroyed successfully'
  );
END;
$$;
