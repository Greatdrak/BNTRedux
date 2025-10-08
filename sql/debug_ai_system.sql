-- Debug AI System
-- Test script to check AI player status and debug the system

-- 1. Check AI player status
SELECT 
  p.id,
  p.handle,
  p.turns,
  p.current_sector,
  s.credits,
  s.hull,
  s.hull_max
FROM public.players p
JOIN public.ships s ON s.player_id = p.id
WHERE p.universe_id = '3c491d51-61e2-4969-ba3e-142d4f5747d8' 
  AND p.is_ai = true
ORDER BY p.turns DESC, s.credits DESC;

-- 2. Test AI decision making for one player
SELECT ai_make_decision(p.id) as decision
FROM public.players p
WHERE p.universe_id = '3c491d51-61e2-4969-ba3e-142d4f5747d8' 
  AND p.is_ai = true
  AND COALESCE(p.turns, 0) > 0
LIMIT 1;

-- 3. Test AI action execution for one player
SELECT ai_execute_action(
  p.id, 
  '3c491d51-61e2-4969-ba3e-142d4f5747d8', 
  'explore'
) as result
FROM public.players p
WHERE p.universe_id = '3c491d51-61e2-4969-ba3e-142d4f5747d8' 
  AND p.is_ai = true
  AND COALESCE(p.turns, 0) > 0
LIMIT 1;

-- 4. Test the full AI runner
SELECT run_ai_player_actions('3c491d51-61e2-4969-ba3e-142d4f5747d8');
