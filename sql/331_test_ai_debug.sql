-- Test the debug AI system directly
-- This will help us see what's happening without waiting for cron

CREATE OR REPLACE FUNCTION public.test_ai_debug_system(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Clear old debug logs first
  DELETE FROM public.ai_action_log 
  WHERE universe_id = p_universe_id 
    AND action_type LIKE 'Debug:%'
    AND created_at < NOW() - INTERVAL '1 hour';
  
  -- Run the debug AI system
  SELECT run_ai_player_actions_debug(p_universe_id) INTO v_result;
  
  -- Return both the result and a summary of logs
  RETURN jsonb_build_object(
    'ai_result', v_result,
    'debug_logs_count', (
      SELECT COUNT(*) 
      FROM public.ai_action_log 
      WHERE universe_id = p_universe_id 
        AND action_type LIKE 'Debug:%'
        AND created_at > NOW() - INTERVAL '5 minutes'
    )
  );
END;
$$;
