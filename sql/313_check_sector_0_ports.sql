-- Migration: 313_check_sector_0_ports.sql
-- Purpose: Check port stock levels in sector 0

SELECT 
  p.id as port_id,
  p.kind as port_type,
  p.ore,
  p.organics,
  p.goods,
  p.energy,
  s.number as sector_number,
  u.name as universe_name
FROM public.ports p
JOIN public.sectors s ON s.id = p.sector_id
JOIN public.universes u ON u.id = s.universe_id
WHERE s.number = 0
ORDER BY p.kind;
