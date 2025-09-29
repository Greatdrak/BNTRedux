-- Query to show all AI players and their current sectors
SELECT 
  p.handle as ai_name,
  p.is_ai,
  p.turns,
  p.ai_personality,
  s.number as sector_number,
  s.id as sector_id,
  sh.name as ship_name,
  sh.hull,
  sh.credits as ship_credits
FROM players p
LEFT JOIN sectors s ON p.current_sector = s.id
LEFT JOIN ships sh ON sh.player_id = p.id
WHERE p.is_ai = true
ORDER BY s.number, p.handle;
