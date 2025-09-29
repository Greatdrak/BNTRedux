-- Debug why AI players aren't taking actions

-- Check AI player details and their current state
SELECT 
    'AI Player Details' as check_name,
    p.handle as player_name,
    p.ai_personality,
    s.credits,
    s.ore,
    s.organics, 
    s.goods,
    s.energy,
    s.colonists,
    s.fighters,
    s.torpedoes,
    sec.number as sector_number,
    -- Check if there are ports in their sector
    (SELECT COUNT(*) FROM ports WHERE sector_id = sec.id) as ports_in_sector,
    -- Check if there are unclaimed planets in their sector
    (SELECT COUNT(*) FROM planets WHERE sector_id = sec.id AND owner_player_id IS NULL) as unclaimed_planets,
    -- Check if there are enemy ships in their sector
    (SELECT COUNT(*) FROM players p2 
     WHERE p2.current_sector = sec.id AND p2.is_ai = FALSE) as enemy_ships
FROM players p
JOIN ships s ON p.id = s.player_id
JOIN sectors sec ON p.current_sector = sec.id
WHERE p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
AND p.is_ai = TRUE
ORDER BY p.handle
LIMIT 3; -- Just show first 3 for analysis

-- Check AI memory status
SELECT 
    'AI Memory Status' as check_name,
    p.handle as player_name,
    apm.current_goal,
    apm.last_action,
    apm.owned_planets,
    apm.last_profit,
    apm.consecutive_losses
FROM players p
LEFT JOIN ai_player_memory apm ON p.id = apm.player_id
WHERE p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
AND p.is_ai = TRUE
ORDER BY p.handle
LIMIT 3;
