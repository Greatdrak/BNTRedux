-- Debug universe mismatch issue in auto-trade
-- Run this to check for universe consistency issues

-- Check for ports in sectors with mismatched universe_ids
SELECT 
  p.id as port_id,
  p.kind as port_kind,
  s.id as sector_id,
  s.number as sector_number,
  s.universe_id as sector_universe_id,
  'Port sector universe mismatch' as issue
FROM ports p
JOIN sectors s ON s.id = p.sector_id
WHERE s.universe_id IS NULL OR s.universe_id = '00000000-0000-0000-0000-000000000000'::uuid;

-- Check for players in sectors with mismatched universe_ids
SELECT 
  pl.id as player_id,
  pl.handle,
  pl.universe_id as player_universe_id,
  s.id as sector_id,
  s.number as sector_number,
  s.universe_id as sector_universe_id,
  'Player sector universe mismatch' as issue
FROM players pl
JOIN sectors s ON s.id = pl.current_sector
WHERE pl.universe_id != s.universe_id;

-- Check for ports without sectors
SELECT 
  p.id as port_id,
  p.kind as port_kind,
  p.sector_id,
  'Port without sector' as issue
FROM ports p
LEFT JOIN sectors s ON s.id = p.sector_id
WHERE s.id IS NULL;

-- Check for sectors without universe_id
SELECT 
  s.id as sector_id,
  s.number as sector_number,
  s.universe_id,
  'Sector without universe' as issue
FROM sectors s
WHERE s.universe_id IS NULL;

-- Sample data check - show a few ports and their universe info
SELECT 
  p.id as port_id,
  p.kind as port_kind,
  s.number as sector_number,
  s.universe_id as sector_universe_id,
  u.name as universe_name
FROM ports p
JOIN sectors s ON s.id = p.sector_id
LEFT JOIN universes u ON u.id = s.universe_id
LIMIT 10;
