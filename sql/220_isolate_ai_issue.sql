-- Simple test to isolate the AI function issue

-- Test 1: Just try to call the enhanced AI function and see what happens
SELECT public.run_enhanced_ai_actions('34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID) as result;

-- Test 2: Check if there are any errors in the AI functions by testing them individually
-- Let's test the ai_make_decision function directly
SELECT 
    'AI Decision Test' as test_name,
    p.handle as player_name,
    p.ai_personality,
    s.credits,
    sec.number as sector_number,
    (SELECT COUNT(*) FROM ports WHERE sector_id = sec.id) as ports_in_sector,
    (SELECT COUNT(*) FROM planets WHERE sector_id = sec.id AND owner_player_id IS NULL) as unclaimed_planets
FROM players p
JOIN ships s ON p.id = s.player_id
JOIN sectors sec ON p.current_sector = sec.id
WHERE p.handle = 'AI_Alpha' 
AND p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID;

-- Test 3: Check if the AI functions exist and are callable
SELECT 
    'Function Existence Check' as test_name,
    proname as function_name,
    proargnames as argument_names
FROM pg_proc 
WHERE proname IN ('ai_make_decision', 'ai_execute_action', 'ai_strategic_explore', 'ai_claim_planet', 'ai_optimize_trading')
ORDER BY proname;
