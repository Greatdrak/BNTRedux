-- Simple test to isolate the cron function issue

-- Test 1: Just try to call the cron function and see what happens
SELECT public.cron_run_ai_actions('16b343e6-0f4c-41ff-8ae5-107bfa104efb'::UUID) as cron_result;

-- Test 2: Try to call the enhanced AI function directly
SELECT public.run_enhanced_ai_actions('16b343e6-0f4c-41ff-8ae5-107bfa104efb'::UUID) as enhanced_ai_result;

-- Test 3: Check if there are any AI players in that specific universe
SELECT COUNT(*) as ai_players_in_universe 
FROM players p
JOIN ships s ON p.id = s.player_id
JOIN sectors sec ON p.current_sector = sec.id
WHERE p.universe_id = '16b343e6-0f4c-41ff-8ae5-107bfa104efb'::UUID 
AND p.is_ai = TRUE;
