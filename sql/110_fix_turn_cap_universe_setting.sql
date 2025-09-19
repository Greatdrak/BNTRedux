-- Fix Turn Cap to Use Universe Settings Instead of Player Column
-- Remove turn_cap from players table and update all code to use max_accumulated_turns from universe_settings

-- Update the turn generation RPC to use universe settings
CREATE OR REPLACE FUNCTION generate_turns_for_universe(
  p_universe_id UUID,
  p_turns_to_add INTEGER
)
RETURNS TABLE(
  players_updated INTEGER,
  total_turns_generated INTEGER,
  players_at_cap INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_players_updated INTEGER := 0;
  v_total_turns_generated INTEGER := 0;
  v_turn_cap INTEGER;
BEGIN
  -- Get the turn cap from universe settings
  SELECT max_accumulated_turns INTO v_turn_cap
  FROM public.universe_settings
  WHERE universe_id = p_universe_id;
  
  -- If no universe settings found, use default
  IF v_turn_cap IS NULL THEN
    v_turn_cap := 5000; -- Default from universe_settings schema
  END IF;
  
  -- Update turns for all players in the universe who haven't reached their cap
  WITH updated_players AS (
    UPDATE public.players 
    SET 
      turns = LEAST(turns + p_turns_to_add, v_turn_cap),
      last_turn_ts = NOW()
    WHERE 
      universe_id = p_universe_id 
      AND turns < v_turn_cap
    RETURNING id, (LEAST(turns + p_turns_to_add, v_turn_cap) - turns) as turns_added
  )
  SELECT 
    COUNT(*)::INTEGER,
    COALESCE(SUM(turns_added), 0)::INTEGER
  INTO v_players_updated, v_total_turns_generated
  FROM updated_players;
  
  -- Return the results
  RETURN QUERY SELECT v_players_updated, v_total_turns_generated;
END;
$$;

-- Update the old regen RPC to also use universe settings
CREATE OR REPLACE FUNCTION public.regen_turns_for_universe(p_universe_id uuid)
RETURNS TABLE(
  players_updated INTEGER,
  total_turns_generated INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_players_updated INTEGER := 0;
  v_total_turns_generated INTEGER := 0;
  v_turn_cap INTEGER;
BEGIN
  -- Get the turn cap from universe settings
  SELECT max_accumulated_turns INTO v_turn_cap
  FROM public.universe_settings
  WHERE universe_id = p_universe_id;
  
  -- If no universe settings found, use default
  IF v_turn_cap IS NULL THEN
    v_turn_cap := 5000; -- Default from universe_settings schema
  END IF;
  
  -- Add +1 turn to players with turns < turn_cap
  WITH updated_players AS (
    UPDATE public.players 
    SET 
      turns = LEAST(turns + 1, v_turn_cap),
      last_turn_ts = NOW()
    WHERE 
      universe_id = p_universe_id 
      AND turns < v_turn_cap
    RETURNING id, (LEAST(turns + 1, v_turn_cap) - turns) as turns_added
  )
  SELECT 
    COUNT(*)::INTEGER,
    COALESCE(SUM(turns_added), 0)::INTEGER
  INTO v_players_updated, v_total_turns_generated
  FROM updated_players;
  
  -- Return the results
  RETURN QUERY SELECT v_players_updated, v_total_turns_generated;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION generate_turns_for_universe(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION generate_turns_for_universe(UUID, INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.regen_turns_for_universe(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.regen_turns_for_universe(uuid) TO service_role;

-- Set ownership
ALTER FUNCTION generate_turns_for_universe(UUID, INTEGER) OWNER TO postgres;
ALTER FUNCTION public.regen_turns_for_universe(uuid) OWNER TO postgres;
