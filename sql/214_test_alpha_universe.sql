-- Test the cron function with the Alpha universe (where AI players actually exist)

-- Test 1: AI Players Status in Alpha universe
SELECT 
    'AI Players Status in Alpha' as test_name,
    p.handle as player_name,
    p.is_ai,
    p.ai_personality,
    s.credits,
    sec.number as sector_number,
    CASE WHEN apm.player_id IS NOT NULL THEN 'HAS_MEMORY' ELSE 'NO_MEMORY' END as memory_status
FROM players p
JOIN ships s ON p.id = s.player_id
JOIN sectors sec ON p.current_sector = sec.id
LEFT JOIN ai_player_memory apm ON p.id = apm.player_id
WHERE p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
AND p.is_ai = TRUE
ORDER BY p.handle
LIMIT 5; -- Just show first 5 for brevity

-- Test 2: Cron Function Test (should call enhanced AI)
SELECT 'Cron Function Test' as test_name, public.cron_run_ai_actions('34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID) as result;

-- Test 3: Enhanced AI Direct Test
SELECT 'Enhanced AI Direct Test' as test_name, public.run_enhanced_ai_actions('34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID) as result;
