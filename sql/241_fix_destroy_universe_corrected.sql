-- Migration: 241_fix_destroy_universe_corrected.sql
-- Fix the destroy_universe function with correct column references

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
  v_deleted_count INTEGER := 0;
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
    -- Delete all data in dependency order
    -- Handle tables that might not exist gracefully
    
    -- Delete from trades table (if it exists) - uses player_id foreign key
    BEGIN
      DELETE FROM trades WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % trades', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'trades table does not exist, skipping';
    END;
    
    -- Delete from combats table (if it exists) - uses player_id foreign keys
    BEGIN
      DELETE FROM combats WHERE attacker_id IN (SELECT id FROM players WHERE universe_id = p_universe_id) 
        OR defender_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % combats', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'combats table does not exist, skipping';
    END;
    
    -- Delete from visited table (if it exists) - uses sector_id foreign key
    BEGIN
      DELETE FROM visited WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % visited records', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'visited table does not exist, skipping';
    END;
    
    -- Delete from scans table (if it exists) - uses sector_id foreign key
    BEGIN
      DELETE FROM scans WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % scans', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'scans table does not exist, skipping';
    END;
    
    -- Delete from favorites table (if it exists) - uses sector_id foreign key
    BEGIN
      DELETE FROM favorites WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % favorites', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'favorites table does not exist, skipping';
    END;
    
    -- Delete from planets table - uses sector_id foreign key
    DELETE FROM planets WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % planets', v_deleted_count;
    
    -- Delete from ports table - uses sector_id foreign key
    DELETE FROM ports WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % ports', v_deleted_count;
    
    -- Delete from ships table - uses player_id foreign key
    DELETE FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % ships', v_deleted_count;
    
    -- Delete from inventories table (if it exists) - uses player_id foreign key
    BEGIN
      DELETE FROM inventories WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % inventory records', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'inventories table does not exist, skipping';
    END;
    
    -- Delete from ai_player_memory table (if it exists) - uses player_id foreign key
    BEGIN
      DELETE FROM ai_player_memory WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % AI memory records', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'ai_player_memory table does not exist, skipping';
    END;
    
    -- Delete from player_rankings table (if it exists) - HAS universe_id column
    BEGIN
      DELETE FROM player_rankings WHERE universe_id = p_universe_id;
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % player rankings', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'player_rankings table does not exist, skipping';
    END;
    
    -- Delete from ranking_history table (if it exists) - HAS universe_id column
    BEGIN
      DELETE FROM ranking_history WHERE universe_id = p_universe_id;
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % ranking history records', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'ranking_history table does not exist, skipping';
    END;
    
    -- Delete from trade_routes table (if it exists) - HAS universe_id column
    BEGIN
      DELETE FROM trade_routes WHERE universe_id = p_universe_id;
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % trade routes', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'trade_routes table does not exist, skipping';
    END;
    
    -- Delete from route_executions table (if it exists) - HAS universe_id column
    BEGIN
      DELETE FROM route_executions WHERE universe_id = p_universe_id;
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % route executions', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'route_executions table does not exist, skipping';
    END;
    
    -- Delete from route_waypoints table (if it exists) - uses route_id foreign key
    BEGIN
      DELETE FROM route_waypoints WHERE route_id IN (SELECT id FROM trade_routes WHERE universe_id = p_universe_id);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % route waypoints', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'route_waypoints table does not exist, skipping';
    END;
    
    -- Delete from route_profitability table (if it exists) - uses route_id foreign key
    BEGIN
      DELETE FROM route_profitability WHERE route_id IN (SELECT id FROM trade_routes WHERE universe_id = p_universe_id);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % route profitability records', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'route_profitability table does not exist, skipping';
    END;
    
    -- Delete from universe_settings table (if it exists) - HAS universe_id column
    BEGIN
      DELETE FROM universe_settings WHERE universe_id = p_universe_id;
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
      RAISE NOTICE 'Deleted % universe settings', v_deleted_count;
    EXCEPTION
      WHEN undefined_table THEN
        RAISE NOTICE 'universe_settings table does not exist, skipping';
    END;
    
    -- Delete players - HAS universe_id column
    DELETE FROM players WHERE universe_id = p_universe_id;
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % players', v_deleted_count;
    
    -- Delete warps - HAS universe_id column
    DELETE FROM warps WHERE universe_id = p_universe_id;
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % warps', v_deleted_count;
    
    -- Delete sectors - HAS universe_id column
    DELETE FROM sectors WHERE universe_id = p_universe_id;
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % sectors', v_deleted_count;
    
    -- Finally, delete the universe itself
    DELETE FROM universes WHERE id = p_universe_id;
    
  EXCEPTION
    WHEN OTHERS THEN
      RAISE NOTICE 'Error during deletion: %', SQLERRM;
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
