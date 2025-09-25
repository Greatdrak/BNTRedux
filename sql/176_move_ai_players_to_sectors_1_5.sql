-- Move all existing AI players to sectors 1-5
-- This concentrates AI players in specific sectors for better gameplay

-- First, ensure sectors 1-5 exist
INSERT INTO sectors (id, universe_id, number)
SELECT 
  gen_random_uuid() as id,
  '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid as universe_id,
  generate_series(1, 5) as number
ON CONFLICT (universe_id, number) DO NOTHING;

-- Update all AI players to be in sectors 1-5
UPDATE players 
SET current_sector = (
  SELECT id FROM sectors 
  WHERE universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid 
  AND number IN (1, 2, 3, 4, 5)
  ORDER BY random()
  LIMIT 1
)
WHERE is_ai = true 
AND universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid;

-- Show results
SELECT 
  p.handle,
  s.number as sector_number,
  p.is_ai
FROM players p
JOIN sectors s ON p.current_sector = s.id
WHERE p.is_ai = true 
AND p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid
ORDER BY s.number, p.handle;
