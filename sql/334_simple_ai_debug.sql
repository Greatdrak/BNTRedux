-- Simplified debug function to isolate the issue
-- This will help us find where the debug function is failing

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
      'total_ai', v_total_ai,
      'ai_with_turns', v_ai_with_turns,
      'universe_id', p_universe_id
    );
    
  EXCEPTION WHEN OTHERS THEN
    v_error_msg := SQLERRM;
    RETURN jsonb_build_object(
      'success', false,
      'error', v_error_msg,
      'universe_id', p_universe_id
    );
  END;
END;
$$;
