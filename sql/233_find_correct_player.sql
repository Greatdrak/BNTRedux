-- Check for multiple players and find the correct one

-- Test 1: Check all players with Alpha or Nate in the name
SELECT 
    'All Players' as check_name,
    p.id as player_id,
    p.handle as player_name,
    p.user_id,
    p.universe_id,
    p.current_sector,
    s.number as current_sector_number
FROM players p
LEFT JOIN sectors s ON p.current_sector = s.id
WHERE p.handle LIKE '%Alpha%' OR p.handle LIKE '%Nate%' OR p.handle LIKE '%Admin%'
ORDER BY p.handle;

-- Test 2: Check which player owns the planet
SELECT 
    'Planet Owner Details' as check_name,
    p.id as planet_id,
    p.name as planet_name,
    p.owner_player_id,
    pl.handle as owner_name,
    pl.user_id as owner_user_id,
    pl.universe_id as owner_universe_id
FROM planets p
JOIN players pl ON p.owner_player_id = pl.id
WHERE p.name = 'Jizzy';

-- Test 3: Check if there are multiple players for the same user
SELECT 
    'User Players' as check_name,
    p.id as player_id,
    p.handle as player_name,
    p.user_id,
    p.universe_id,
    COUNT(*) OVER (PARTITION BY p.user_id) as players_per_user
FROM players p
WHERE p.handle LIKE '%Alpha%' OR p.handle LIKE '%Nate%' OR p.handle LIKE '%Admin%'
ORDER BY p.user_id, p.handle;
