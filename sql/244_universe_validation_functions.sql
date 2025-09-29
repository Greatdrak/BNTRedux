-- Migration: 244_universe_validation_functions.sql
-- Add helper functions to validate universe existence and handle deleted universes

-- Function to check if a universe exists
CREATE OR REPLACE FUNCTION public.universe_exists(p_universe_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN EXISTS(SELECT 1 FROM universes WHERE id = p_universe_id);
END;
$$;

-- Function to get the first available universe (for players whose universe was deleted)
CREATE OR REPLACE FUNCTION public.get_first_available_universe()
RETURNS TABLE(universe_id UUID, universe_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT u.id, u.name
  FROM universes u
  ORDER BY u.created_at ASC
  LIMIT 1;
END;
$$;

-- Function to clean up orphaned player data (when universe is deleted but player session still exists)
CREATE OR REPLACE FUNCTION public.cleanup_orphaned_player_data(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_orphaned_players INTEGER := 0;
  v_orphaned_ships INTEGER := 0;
  v_orphaned_planets INTEGER := 0;
  v_first_universe RECORD;
BEGIN
  -- Count orphaned data
  SELECT COUNT(*) INTO v_orphaned_players 
  FROM players p 
  WHERE p.user_id = p_user_id 
  AND NOT EXISTS(SELECT 1 FROM universes u WHERE u.id = p.universe_id);
  
  SELECT COUNT(*) INTO v_orphaned_ships 
  FROM ships s 
  JOIN players p ON s.player_id = p.id
  WHERE p.user_id = p_user_id 
  AND NOT EXISTS(SELECT 1 FROM universes u WHERE u.id = p.universe_id);
  
  SELECT COUNT(*) INTO v_orphaned_planets 
  FROM planets pl
  JOIN sectors sec ON pl.sector_id = sec.id
  WHERE pl.owner_player_id IN (SELECT id FROM players WHERE user_id = p_user_id)
  AND NOT EXISTS(SELECT 1 FROM universes u WHERE u.id = sec.universe_id);
  
  -- Get first available universe for potential migration
  SELECT * INTO v_first_universe FROM public.get_first_available_universe();
  
  RETURN jsonb_build_object(
    'orphaned_players', v_orphaned_players,
    'orphaned_ships', v_orphaned_ships,
    'orphaned_planets', v_orphaned_planets,
    'first_available_universe', CASE 
      WHEN v_first_universe.universe_id IS NOT NULL THEN 
        jsonb_build_object('id', v_first_universe.universe_id, 'name', v_first_universe.universe_name)
      ELSE NULL 
    END,
    'has_orphaned_data', (v_orphaned_players > 0 OR v_orphaned_ships > 0 OR v_orphaned_planets > 0)
  );
END;
$$;
