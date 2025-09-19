-- Diagnose port values to find what's causing integer overflow
-- Check for any ports with values that could cause integer overflow

SELECT 
  p.id,
  p.kind,
  p.ore,
  p.organics,
  p.goods,
  p.energy,
  s.number as sector_number,
  u.name as universe_name
FROM ports p
JOIN sectors s ON s.id = p.sector_id
JOIN universes u ON u.id = s.universe_id
WHERE p.kind IN ('ore', 'organics', 'goods', 'energy')
ORDER BY 
  GREATEST(p.ore, p.organics, p.goods, p.energy) DESC
LIMIT 20;
