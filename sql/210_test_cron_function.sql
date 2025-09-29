-- Test which version of cron_run_ai_actions is actually running
-- This will tell us if it's using the old or new AI system

-- Test the cron function with a real universe
SELECT 
    'Cron Function Test' as test_name,
    public.cron_run_ai_actions(
        (SELECT id FROM universes LIMIT 1)
    ) as result;

-- Also test the enhanced AI function directly
SELECT 
    'Enhanced AI Direct Test' as test_name,
    public.run_enhanced_ai_actions(
        (SELECT id FROM universes LIMIT 1)
    ) as result;

-- Check what AI players exist and their current state
SELECT 
    'AI Players Status' as test_name,
    p.handle as player_name,
    p.is_ai,
    p.ai_personality,
    s.credits,
    sec.number as sector_number,
    CASE WHEN mem.player_id IS NOT NULL THEN 'HAS_MEMORY' ELSE 'NO_MEMORY' END as memory_status
FROM players p
JOIN ships s ON p.id = s.player_id
JOIN sectors sec ON p.current_sector = sec.id
LEFT JOIN ai_player_memory mem ON p.id = mem.player_id
WHERE p.is_ai = TRUE
LIMIT 5;
