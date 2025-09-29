-- Check what happened when we ran enhanced AI after moving AI_Alpha

-- Test 1: Run enhanced AI again to see if AI_Alpha takes actions now
SELECT 'Enhanced AI Test After Move' as test_name, 
       public.run_enhanced_ai_actions('34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID) as result;

-- Test 2: Check if AI_Alpha's status changed (credits, cargo, etc.)
SELECT 
    'AI_Alpha Status After AI Run' as check_name,
    p.handle as player_name,
    s.credits,
    s.ore,
    s.organics,
    s.goods,
    s.energy,
    s.colonists,
    s.fighters,
    s.torpedoes,
    sec.number as sector_number,
    -- Check if AI_Alpha claimed the planet
    (SELECT COUNT(*) FROM planets WHERE sector_id = sec.id AND owner_player_id = p.id) as owned_planets
FROM players p
JOIN ships s ON p.id = s.player_id
JOIN sectors sec ON p.current_sector = sec.id
WHERE p.handle = 'AI_Alpha' 
AND p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID;

-- Test 3: Check if the planet in sector 3 was claimed
SELECT 
    'Planet Status in Sector 3' as check_name,
    p.name as planet_name,
    p.owner_player_id,
    CASE 
        WHEN p.owner_player_id IS NULL THEN 'UNCLAIMED'
        ELSE 'CLAIMED'
    END as status
FROM planets p
JOIN sectors s ON p.sector_id = s.id
WHERE s.number = 3 AND s.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID;
