-- Critical fixes for player registration and universe management

-- Step 1: Add missing constraint to prevent duplicate players per user per universe
-- This is the root cause of the multiple player issue
DO $$
BEGIN
    -- Add the constraint only if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'players_user_id_universe_id_key'
    ) THEN
        ALTER TABLE players ADD CONSTRAINT players_user_id_universe_id_key UNIQUE (user_id, universe_id);
    END IF;
END $$;

-- Step 2: Update the universe wipe function to handle all new tables
CREATE OR REPLACE FUNCTION public.destroy_universe(p_universe_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe_name TEXT;
  v_player_count INTEGER;
  v_ship_count INTEGER;
  v_sector_count INTEGER;
  v_planet_count INTEGER;
  v_port_count INTEGER;
BEGIN
  -- Get universe name for logging
  SELECT name INTO v_universe_name FROM universes WHERE id = p_universe_id;
  
  IF v_universe_name IS NULL THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_not_found', 'message', 'Universe not found'));
  END IF;
  
  -- Count affected entities for reporting
  SELECT COUNT(*) INTO v_player_count FROM players WHERE universe_id = p_universe_id;
  SELECT COUNT(*) INTO v_ship_count FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  SELECT COUNT(*) INTO v_sector_count FROM sectors WHERE universe_id = p_universe_id;
  SELECT COUNT(*) INTO v_planet_count FROM planets WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  SELECT COUNT(*) INTO v_port_count FROM ports WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  
  -- Delete all data in dependency order (CASCADE will handle most, but we'll be explicit)
  
  -- Delete AI-related data
  DELETE FROM ai_player_memory WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  
  -- Delete ranking data
  DELETE FROM player_rankings WHERE universe_id = p_universe_id;
  DELETE FROM ranking_history WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  
  -- Delete trade and combat data
  DELETE FROM trades WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  DELETE FROM combats WHERE attacker_id IN (SELECT id FROM players WHERE universe_id = p_universe_id) 
    OR defender_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  
  -- Delete exploration data
  DELETE FROM visited WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  DELETE FROM scans WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  DELETE FROM favorites WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  
  -- Delete trade route data
  DELETE FROM route_executions WHERE route_id IN (
    SELECT tr.id FROM trade_routes tr 
    JOIN players p ON tr.player_id = p.id 
    WHERE p.universe_id = p_universe_id
  );
  DELETE FROM route_profitability WHERE route_id IN (
    SELECT tr.id FROM trade_routes tr 
    JOIN players p ON tr.player_id = p.id 
    WHERE p.universe_id = p_universe_id
  );
  DELETE FROM route_waypoints WHERE route_id IN (
    SELECT tr.id FROM trade_routes tr 
    JOIN players p ON tr.player_id = p.id 
    WHERE p.universe_id = p_universe_id
  );
  DELETE FROM trade_routes WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  
  -- Delete universe-specific data
  DELETE FROM planets WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  DELETE FROM ports WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  DELETE FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  DELETE FROM inventories WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  DELETE FROM players WHERE universe_id = p_universe_id;
  DELETE FROM warps WHERE universe_id = p_universe_id;
  DELETE FROM sectors WHERE universe_id = p_universe_id;
  
  -- Delete universe settings
  DELETE FROM universe_settings WHERE universe_id = p_universe_id;
  
  -- Finally delete the universe itself
  DELETE FROM universes WHERE id = p_universe_id;
  
  -- Return success with comprehensive statistics
  RETURN jsonb_build_object(
    'ok', true,
    'universe_name', v_universe_name,
    'players_deleted', v_player_count,
    'ships_deleted', v_ship_count,
    'sectors_deleted', v_sector_count,
    'planets_deleted', v_planet_count,
    'ports_deleted', v_port_count,
    'message', 'Universe destroyed successfully with all associated data'
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'error', jsonb_build_object(
        'code', 'destroy_failed',
        'message', 'Failed to destroy universe: ' || SQLERRM
      )
    );
END;
$$;

-- Step 3: Verify the constraint was added
SELECT 
  'Constraint Check' as check_name,
  conname as constraint_name,
  contype as constraint_type,
  pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint 
WHERE conrelid = 'players'::regclass 
AND conname = 'players_user_id_universe_id_key';

-- Step 4: Check for existing duplicate players that need cleanup
SELECT 
  'Duplicate Players Check' as check_name,
  user_id,
  universe_id,
  COUNT(*) as player_count,
  STRING_AGG(handle, ', ') as player_handles
FROM players 
GROUP BY user_id, universe_id 
HAVING COUNT(*) > 1
ORDER BY player_count DESC;
