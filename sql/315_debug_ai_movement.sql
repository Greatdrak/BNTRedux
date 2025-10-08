-- Migration: 315_debug_ai_movement.sql
-- Purpose: Debug AI movement failures

-- Check what warps are available from sector 0
SELECT 
  w.from_sector,
  w.to_sector,
  s1.number as from_sector_number,
  s2.number as to_sector_number
FROM public.warps w
JOIN public.sectors s1 ON s1.id = w.from_sector
JOIN public.sectors s2 ON s2.id = w.to_sector
WHERE s1.number = 0
LIMIT 10;

-- Check if sector 0 exists and has a valid sector_id
SELECT 
  s.id,
  s.number,
  u.name as universe_name
FROM public.sectors s
JOIN public.universes u ON u.id = s.universe_id
WHERE s.number = 0;
