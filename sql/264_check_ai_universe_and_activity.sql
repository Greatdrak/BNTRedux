-- Check AI players universe and recent activity
SELECT 
  p.handle as ai_name,
  p.universe_id,
  u.name as universe_name,
  s.number as sector_number,
  p.ai_personality,
  p.turns,
  sh.credits as ship_credits,
  p.created_at
FROM players p
LEFT JOIN universes u ON p.universe_id = u.id
LEFT JOIN sectors s ON p.current_sector = s.id
LEFT JOIN ships sh ON sh.player_id = p.id
WHERE p.is_ai = true
ORDER BY s.number, p.handle;
