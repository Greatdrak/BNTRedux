-- Test the cron function directly
-- This will help us see if the cron function is working

CREATE OR REPLACE FUNCTION public.test_cron_function(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Test the cron function directly
  SELECT cron_run_ai_actions_safe(p_universe_id) INTO v_result;
  RETURN v_result;
END;
$$;
