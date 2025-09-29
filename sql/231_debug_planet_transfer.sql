-- Debug the planet transfer issue

-- Test 1: Check if the planet exists and who owns it
SELECT 
    'Planet Debug' as check_name,
    p.id as planet_id,
    p.name as planet_name,
    p.owner_player_id,
    s.number as sector_number,
    s.universe_id,
    pl.handle as owner_name
FROM planets p
JOIN sectors s ON p.sector_id = s.id
LEFT JOIN players pl ON p.owner_player_id = pl.id
WHERE p.name = 'Jizzy' OR p.name LIKE '%Jizzy%'
ORDER BY p.name;

-- Test 2: Check your player data
SELECT 
    'Player Debug' as check_name,
    p.id as player_id,
    p.handle as player_name,
    p.user_id,
    p.universe_id,
    p.current_sector
FROM players p
WHERE p.handle = 'Alpha' OR p.handle LIKE '%Alpha%'
ORDER BY p.handle;

-- Test 3: Check the relationship between planet and sector
SELECT 
    'Planet-Sector Relationship' as check_name,
    p.id as planet_id,
    p.name as planet_name,
    p.sector_id,
    s.id as sector_id_check,
    s.number as sector_number,
    s.universe_id
FROM planets p
JOIN sectors s ON p.sector_id = s.id
WHERE p.name = 'Jizzy' OR p.name LIKE '%Jizzy%'
LIMIT 5;
