-- Check AI ship names and details
SELECT 
  p.handle as ai_name,
  s.name as ship_name,
  s.hull,
  s.credits,
  p.current_sector,
  sec.number as sector_number
FROM players p
JOIN ships s ON s.player_id = p.id
LEFT JOIN sectors sec ON p.current_sector = sec.id
WHERE p.is_ai = true
ORDER BY sec.number, p.handle;
