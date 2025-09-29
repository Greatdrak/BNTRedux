-- Find your actual player name in the Alpha universe

-- Test 1: Check all players in the Alpha universe
SELECT 
    'Players in Alpha Universe' as check_name,
    p.id as player_id,
    p.handle as player_name,
    p.user_id,
    p.universe_id,
    u.name as universe_name,
    p.current_sector,
    s.number as current_sector_number
FROM players p
JOIN universes u ON p.universe_id = u.id
LEFT JOIN sectors s ON p.current_sector = s.id
WHERE u.name = 'Alpha'
ORDER BY p.handle;

-- Test 2: Check which player owns the planet Jizzy
SELECT 
    'Planet Owner in Alpha Universe' as check_name,
    p.id as planet_id,
    p.name as planet_name,
    p.owner_player_id,
    pl.handle as owner_name,
    pl.user_id as owner_user_id,
    u.name as universe_name
FROM planets p
JOIN players pl ON p.owner_player_id = pl.id
JOIN universes u ON pl.universe_id = u.id
WHERE p.name = 'Jizzy' AND u.name = 'Alpha';

-- Test 3: Check your current player (the one you're logged in as)
SELECT 
    'Current Player Check' as check_name,
    p.id as player_id,
    p.handle as player_name,
    p.user_id,
    p.universe_id,
    u.name as universe_name
FROM players p
JOIN universes u ON p.universe_id = u.id
WHERE u.name = 'Alpha'
AND p.handle NOT LIKE 'AI_%'  -- Exclude AI players
ORDER BY p.handle;
