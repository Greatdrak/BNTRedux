-- Test the updated AI system

-- Test 1: Run the enhanced AI system
SELECT 'Enhanced AI Test' as test_name, 
       public.run_enhanced_ai_actions('34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID) as result;

-- Test 2: Check if AI players moved or took actions
SELECT 
    'AI Players After Action' as check_name,
    p.handle as player_name,
    s.credits,
    sec.number as sector_number,
    s.ore,
    s.organics,
    s.goods,
    s.hull_lvl,
    s.engine_lvl
FROM players p
JOIN ships s ON p.id = s.player_id
JOIN sectors sec ON p.current_sector = sec.id
WHERE p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
AND p.is_ai = TRUE
ORDER BY p.handle
LIMIT 5;
