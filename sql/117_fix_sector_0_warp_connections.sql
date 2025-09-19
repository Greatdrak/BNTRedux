-- Fix Sector 0 Warp Connections
-- Ensure sector 0 has proper bidirectional warp connections in all universes

-- Add missing warp connections to/from sector 0
-- This ensures sector 0 is accessible via warp navigation

INSERT INTO public.warps (universe_id, from_sector, to_sector)
SELECT 
    s0.universe_id,
    s0.id as from_sector,
    s1.id as to_sector
FROM public.sectors s0
JOIN public.sectors s1 ON s0.universe_id = s1.universe_id
WHERE s0.number = 0 
  AND s1.number = 1
  AND NOT EXISTS (
    SELECT 1 FROM public.warps w 
    WHERE w.universe_id = s0.universe_id 
      AND w.from_sector = s0.id 
      AND w.to_sector = s1.id
  );

-- Add reverse connection (sector 1 to sector 0)
INSERT INTO public.warps (universe_id, from_sector, to_sector)
SELECT 
    s1.universe_id,
    s1.id as from_sector,
    s0.id as to_sector
FROM public.sectors s1
JOIN public.sectors s0 ON s1.universe_id = s0.universe_id
WHERE s1.number = 1 
  AND s0.number = 0
  AND NOT EXISTS (
    SELECT 1 FROM public.warps w 
    WHERE w.universe_id = s1.universe_id 
      AND w.from_sector = s1.id 
      AND w.to_sector = s0.id
  );

-- Verify the fix
SELECT 
    u.name as universe_name,
    s0.number as sector_0_number,
    s1.number as sector_1_number,
    CASE WHEN w1.from_sector IS NOT NULL THEN 'YES' ELSE 'NO' END as sector_0_to_1_exists,
    CASE WHEN w2.from_sector IS NOT NULL THEN 'YES' ELSE 'NO' END as sector_1_to_0_exists
FROM public.universes u
JOIN public.sectors s0 ON u.id = s0.universe_id AND s0.number = 0
JOIN public.sectors s1 ON u.id = s1.universe_id AND s1.number = 1
LEFT JOIN public.warps w1 ON u.id = w1.universe_id AND w1.from_sector = s0.id AND w1.to_sector = s1.id
LEFT JOIN public.warps w2 ON u.id = w2.universe_id AND w2.from_sector = s1.id AND w2.to_sector = s0.id
ORDER BY u.name;
