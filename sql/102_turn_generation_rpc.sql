-- Create RPC function for turn generation
-- This function generates turns for all players in a universe who haven't reached their cap
-- Returns the number of players updated and total turns generated

CREATE OR REPLACE FUNCTION generate_turns_for_universe(
  p_universe_id UUID,
  p_turns_to_add INTEGER
)
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
BEGIN
  -- Update turns for all players in the universe who haven't reached their cap
  WITH updated_players AS (
    UPDATE public.players 
    SET 
      turns = LEAST(turns + p_turns_to_add, turn_cap),
      last_turn_ts = NOW()
    WHERE 
      universe_id = p_universe_id 
      AND turns < turn_cap
    RETURNING id, (LEAST(turns + p_turns_to_add, turn_cap) - turns) as turns_added
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

-- Grant execute permission to authenticated users and service role
GRANT EXECUTE ON FUNCTION generate_turns_for_universe(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION generate_turns_for_universe(UUID, INTEGER) TO service_role;