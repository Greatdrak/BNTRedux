-- Fix Cron AI Function Call
-- 
-- The cron job is calling 'cron_run_ai_actions' but that function doesn't exist.
-- The correct function is 'run_ai_player_actions'.
-- 
-- This migration creates a wrapper function that the cron can call,
-- which then calls the actual AI function.

-- Create the wrapper function that cron expects
CREATE OR REPLACE FUNCTION public.cron_run_ai_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Simply call the existing AI function
    RETURN public.run_ai_player_actions(p_universe_id);
END;
$$;

-- Grant permissions
GRANT ALL ON FUNCTION public.cron_run_ai_actions(UUID) TO anon;
GRANT ALL ON FUNCTION public.cron_run_ai_actions(UUID) TO authenticated;
GRANT ALL ON FUNCTION public.cron_run_ai_actions(UUID) TO service_role;

-- Test the function
SELECT 'Testing cron_run_ai_actions wrapper...' as status;
SELECT cron_run_ai_actions((SELECT id FROM universes LIMIT 1)) as test_result;
