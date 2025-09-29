-- Check player and planet ownership

-- Test 1: Check your player data
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

-- Test 2: Check planet ownership
SELECT 
    'Planet Ownership' as check_name,
    p.id as planet_id,
    p.name as planet_name,
    p.owner_player_id,
    pl.handle as owner_name,
    pl.universe_id as owner_universe_id
FROM planets p
LEFT JOIN players pl ON p.owner_player_id = pl.id
WHERE p.name = 'Jizzy'
ORDER BY p.name;

-- Test 3: Check if you own the planet
SELECT 
    'Ownership Check' as check_name,
    p.id as planet_id,
    p.name as planet_name,
    p.owner_player_id,
    pl.id as your_player_id,
    pl.handle as your_name,
    CASE 
        WHEN p.owner_player_id = pl.id THEN 'YOU OWN IT'
        ELSE 'NOT OWNED BY YOU'
    END as ownership_status
FROM planets p
CROSS JOIN players pl
WHERE p.name = 'Jizzy' 
AND pl.handle = 'Alpha'
ORDER BY p.name;
