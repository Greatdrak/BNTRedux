-- Debug AI actions to see why they're not working
-- Check if AI players exist and their current state

-- 1. Check AI players in universe
SELECT 
  p.handle as ai_name,
  p.is_ai,
  p.ai_personality,
  p.turns,
  p.turns_spent,
  s.number as sector_number,
  sh.credits as ship_credits,
  sh.ore,
  sh.organics,
  sh.goods,
  sh.energy
FROM players p
LEFT JOIN sectors s ON p.current_sector = s.id
LEFT JOIN ships sh ON sh.player_id = p.id
WHERE p.is_ai = true
  AND p.universe_id = (SELECT id FROM universes WHERE name = 'Alpha')
ORDER BY p.handle;

-- 2. Check AI memory state
SELECT 
  p.handle as ai_name,
  m.current_goal,
  m.target_sector_id,
  m.target_planet_id,
  m.last_action,
  m.action_count,
  m.efficiency_score
FROM players p
LEFT JOIN ai_player_memory m ON m.player_id = p.id
WHERE p.is_ai = true
  AND p.universe_id = (SELECT id FROM universes WHERE name = 'Alpha')
ORDER BY p.handle;

-- 3. Test the cron_run_ai_actions function directly
SELECT cron_run_ai_actions((SELECT id FROM universes WHERE name = 'Alpha'));

-- 4. Check if the function exists and what it does
SELECT routine_name, routine_definition 
FROM information_schema.routines 
WHERE routine_name = 'cron_run_ai_actions';

-- 5. Check universe settings for AI
SELECT 
  ai_actions_enabled,
  ai_player_actions_interval_minutes,
  last_ai_player_actions_event
FROM universe_settings 
WHERE universe_id = (SELECT id FROM universes WHERE name = 'Alpha');
