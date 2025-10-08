-- Correct AI Debug Query Based on Actual Schema
-- 
-- From the schema dump, I can see:
-- 1. The players table DOES have an is_ai column (line 6404 in functions dump)
-- 2. The run_ai_player_actions function exists and works with is_ai = TRUE
-- 3. The create_ai_players function exists and creates players with is_ai = TRUE

-- 1. Check if AI players exist
SELECT 
  'AI Players Count' as check_type,
  COUNT(*) as count
FROM players 
WHERE is_ai = true;

-- 2. Check AI players and their current state
SELECT 
  p.handle as ai_name,
  p.is_ai,
  p.turns,
  p.turns_spent,
  s.number as current_sector_number,
  sh.name as ship_name,
  sh.credits as ship_credits,
  sh.ore,
  sh.organics,
  sh.goods,
  sh.energy
FROM players p
LEFT JOIN sectors s ON p.current_sector = s.id
LEFT JOIN ships sh ON sh.player_id = p.id
WHERE p.is_ai = true
ORDER BY p.handle;

-- 3. Test the run_ai_player_actions function directly
-- (Replace with actual universe_id from your system)
SELECT run_ai_player_actions(
  (SELECT id FROM universes LIMIT 1)
) as ai_actions_result;

-- 4. Check if the cron job is calling the right function
-- The cron should be calling run_ai_player_actions, not cron_run_ai_actions
SELECT 
  'Cron should call' as info,
  'run_ai_player_actions(universe_id)' as function_call;

-- 5. Check universe settings for AI actions
SELECT 
  us.ai_player_actions_interval_minutes,
  us.last_ai_player_actions_event,
  u.name as universe_name
FROM universe_settings us
JOIN universes u ON us.universe_id = u.id
LIMIT 1;

-- CONCLUSION:
-- The AI system exists and should work. The issue is likely:
-- 1. No AI players have been created yet
-- 2. The cron job is calling the wrong function name
-- 3. The universe settings might not be configured properly
