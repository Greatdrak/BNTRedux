-- Debug AI System - Simple Test
-- This will help identify why AI players aren't being processed

-- 1. Check if there's an issue with the run_ai_player_actions function
-- Let's create a simple test version that just counts and returns basic info

CREATE OR REPLACE FUNCTION public.debug_ai_system(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_total_ai int;
  v_ai_with_turns int;
  v_player record;
  v_debug_info jsonb;
BEGIN
  -- Count AI players
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  -- Get sample AI player data
  SELECT 
    p.id,
    p.handle,
    p.turns,
    s.credits,
    s.hull
  INTO v_player
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.universe_id = p_universe_id 
    AND p.is_ai = true
    AND COALESCE(p.turns, 0) > 0
  LIMIT 1;
  
  RETURN jsonb_build_object(
    'total_ai', v_total_ai,
    'ai_with_turns', v_ai_with_turns,
    'sample_player', CASE 
      WHEN v_player.id IS NOT NULL THEN
        jsonb_build_object(
          'id', v_player.id,
          'handle', v_player.handle,
          'turns', v_player.turns,
          'credits', v_player.credits,
          'hull', v_player.hull
        )
      ELSE 'no_players_found'
    END
  );
END;
$$;
