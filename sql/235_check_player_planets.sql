-- Check which player you're currently logged in as

-- Test 1: Check which player owns the planet Jizzy
SELECT 
    'Planet Owner Details' as check_name,
    p.id as planet_id,
    p.name as planet_name,
    p.owner_player_id,
    pl.handle as owner_name,
    pl.user_id as owner_user_id
FROM planets p
JOIN players pl ON p.owner_player_id = pl.id
WHERE p.name = 'Jizzy';

-- Test 2: Check all planets owned by each player
SELECT 
    'Player Planet Count' as check_name,
    pl.handle as player_name,
    pl.id as player_id,
    COUNT(p.id) as planets_owned
FROM players pl
LEFT JOIN planets p ON pl.id = p.owner_player_id
WHERE pl.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
GROUP BY pl.id, pl.handle
ORDER BY planets_owned DESC;

-- Test 3: List all planets owned by each player
SELECT 
    'Player Planets' as check_name,
    pl.handle as player_name,
    p.name as planet_name,
    p.id as planet_id,
    s.number as sector_number
FROM players pl
JOIN planets p ON pl.id = p.owner_player_id
JOIN sectors s ON p.sector_id = s.id
WHERE pl.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
ORDER BY pl.handle, p.name;
