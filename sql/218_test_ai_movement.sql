-- Test AI movement logic directly

-- Test 1: Check if AI can move to a different sector
-- Let's manually test moving one AI player to sector 3 (has port + planet)
UPDATE players 
SET current_sector = (SELECT id FROM sectors WHERE number = 3 AND universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID)
WHERE handle = 'AI_Alpha' 
AND universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID;

-- Test 2: Now run enhanced AI again to see if AI_Alpha takes actions
SELECT 'After Moving AI_Alpha to Sector 3' as test_name, 
       public.run_enhanced_ai_actions('34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID) as result;

-- Test 3: Check AI_Alpha's new status
SELECT 
    'AI_Alpha New Status' as check_name,
    p.handle as player_name,
    p.ai_personality,
    s.credits,
    s.ore,
    s.organics,
    s.goods,
    sec.number as sector_number,
    (SELECT COUNT(*) FROM ports WHERE sector_id = sec.id) as ports_in_sector,
    (SELECT COUNT(*) FROM planets WHERE sector_id = sec.id AND owner_player_id IS NULL) as unclaimed_planets
FROM players p
JOIN ships s ON p.id = s.player_id
JOIN sectors sec ON p.current_sector = sec.id
WHERE p.handle = 'AI_Alpha' 
AND p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID;
