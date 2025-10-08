-- Fix the diagnostic function JSON issue
-- The problem was returning a string instead of proper JSON

CREATE OR REPLACE FUNCTION public.diagnose_ai_players(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_total_players int;
  v_ai_players int;
  v_ai_with_turns int;
  v_sample_player jsonb;
BEGIN
  -- Count total players
  SELECT COUNT(*) INTO v_total_players
  FROM public.players p
  WHERE p.universe_id = p_universe_id;
  
  -- Count AI players
  SELECT COUNT(*) INTO v_ai_players
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  -- Count AI players with turns
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  -- Get sample AI player data
  SELECT jsonb_build_object(
    'id', p.id,
    'handle', p.handle,
    'turns', p.turns,
    'is_ai', p.is_ai,
    'universe_id', p.universe_id,
    'credits', s.credits,
    'hull', s.hull
  ) INTO v_sample_player
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true
  LIMIT 1;
  
  RETURN jsonb_build_object(
    'universe_id', p_universe_id,
    'total_players', v_total_players,
    'ai_players', v_ai_players,
    'ai_with_turns', v_ai_with_turns,
    'sample_player', COALESCE(v_sample_player, jsonb_build_object('status', 'no_ai_players_found'))
  );
END;
$$;
