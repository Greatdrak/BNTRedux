-- Quick Fix: Add cron_run_ai_actions wrapper function
-- This fixes the immediate error while preserving existing AI system

CREATE OR REPLACE FUNCTION public.cron_run_ai_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSON;
BEGIN
    -- For now, just use the existing AI system
    -- This will be enhanced later when the full AI system is deployed
    SELECT public.run_ai_player_actions(p_universe_id) INTO v_result;
    
    RETURN v_result;
END;
$$;
