-- Check the actual port structure and existing player functions

-- Test 1: Check what columns actually exist in the ports table
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'ports' 
ORDER BY ordinal_position;

-- Test 2: Check what player functions exist for trading, planet claiming, etc.
SELECT 
    'Player Functions' as check_name,
    proname as function_name,
    proargnames as argument_names
FROM pg_proc 
WHERE proname LIKE '%trade%' OR proname LIKE '%planet%' OR proname LIKE '%claim%' OR proname LIKE '%move%'
ORDER BY proname;

-- Test 3: Check what sectors have unclaimed planets (simplified)
SELECT 
    'Sectors with Unclaimed Planets' as check_name,
    sec.number as sector_number,
    COUNT(p.id) as unclaimed_planets
FROM sectors sec
LEFT JOIN planets p ON sec.id = p.sector_id AND p.owner_player_id IS NULL
WHERE sec.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
GROUP BY sec.number
HAVING COUNT(p.id) > 0
ORDER BY sec.number;
