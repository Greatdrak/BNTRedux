-- Make Enhanced AI Always Enabled (Remove Toggle)
-- Enhanced AI is superior in every way, so it should always be active

-- Enable enhanced AI actions for all existing universes
UPDATE universe_settings 
SET ai_actions_enabled = TRUE 
WHERE ai_actions_enabled IS NULL OR ai_actions_enabled = FALSE;

-- Also ensure the column exists (in case it wasn't added properly)
ALTER TABLE universe_settings ADD COLUMN IF NOT EXISTS ai_actions_enabled BOOLEAN DEFAULT TRUE;

-- Update any universe_settings that don't have this column set
UPDATE universe_settings 
SET ai_actions_enabled = TRUE 
WHERE ai_actions_enabled IS NULL;

-- Since enhanced AI is always enabled, we can remove the column entirely
-- But first, let's update the cron function to always use enhanced AI
DROP FUNCTION IF EXISTS public.cron_run_ai_actions(UUID);

-- Create simplified cron function that always uses enhanced AI
CREATE OR REPLACE FUNCTION public.cron_run_ai_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Always use enhanced AI system (no more toggle needed)
    SELECT public.run_enhanced_ai_actions(p_universe_id) INTO v_result;
    RETURN v_result;
END;
$$;

-- Verify the changes
SELECT 
    universe_id,
    ai_actions_enabled,
    'Enhanced AI always enabled for this universe' as status
FROM universe_settings 
WHERE ai_actions_enabled = TRUE;

-- Show count of universes with enhanced AI
SELECT 
    COUNT(*) as universes_with_enhanced_ai,
    'Enhanced AI is now ALWAYS ACTIVE!' as message
FROM universe_settings 
WHERE ai_actions_enabled = TRUE;
