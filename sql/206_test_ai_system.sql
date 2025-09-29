-- Test Enhanced AI System
-- Run this to see what's happening with the AI system

-- Check if AI players exist
SELECT 
    'AI Players Check' as test,
    COUNT(*) as total_ai_players,
    COUNT(CASE WHEN ai_personality IS NOT NULL THEN 1 END) as with_personalities,
    COUNT(CASE WHEN id IN (SELECT player_id FROM ai_player_memory) THEN 1 END) as with_memory
FROM players 
WHERE is_ai = TRUE;

-- Check if enhanced AI functions exist
SELECT 
    'Function Check' as test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'run_enhanced_ai_actions') 
         THEN 'EXISTS' ELSE 'MISSING' END as run_enhanced_ai_actions,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cron_run_ai_actions') 
         THEN 'EXISTS' ELSE 'MISSING' END as cron_run_ai_actions,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ai_make_decision') 
         THEN 'EXISTS' ELSE 'MISSING' END as ai_make_decision;

-- Test the cron function with a real universe
SELECT 
    'Cron Function Test' as test,
    public.cron_run_ai_actions(
        (SELECT id FROM universes LIMIT 1)
    ) as result;

-- Check universe settings
SELECT 
    'Universe Settings Check' as test,
    universe_id,
    ai_actions_enabled
FROM universe_settings 
LIMIT 5;
