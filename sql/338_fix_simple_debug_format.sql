-- Fix the simple debug function to return the expected format
-- The cron function expects specific field names

CREATE OR REPLACE FUNCTION public.simple_ai_debug(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_total_ai int;
  v_ai_with_turns int;
  v_error_msg text;
BEGIN
  BEGIN
    -- Count AI players
    SELECT COUNT(*) INTO v_total_ai
    FROM public.players p
    WHERE p.universe_id = p_universe_id AND p.is_ai = true;
    
    -- Count AI players with turns
    SELECT COUNT(*) INTO v_ai_with_turns
    FROM public.players p
    WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
    
    RETURN jsonb_build_object(
      'success', true,
      'message', 'ok',
      'ai_total', v_total_ai,
      'ai_with_turns', v_ai_with_turns,
      'ai_with_goal', v_total_ai,
      'actions_taken', 0,
      'players_processed', 0,
      'planets_claimed', 0,
      'upgrades', 0,
      'trades', 0,
      'universe_id', p_universe_id
    );
    
  EXCEPTION WHEN OTHERS THEN
    v_error_msg := SQLERRM;
    RETURN jsonb_build_object(
      'success', false,
      'message', v_error_msg,
      'ai_total', 0,
      'ai_with_turns', 0,
      'ai_with_goal', 0,
      'actions_taken', 0,
      'players_processed', 0,
      'planets_claimed', 0,
      'upgrades', 0,
      'trades', 0,
      'universe_id', p_universe_id
    );
  END;
END;
$$;
