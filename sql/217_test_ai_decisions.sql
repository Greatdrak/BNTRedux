-- Test the AI decision making logic directly

-- Let's manually test what decision an AI player would make
SELECT 
    'AI Decision Test' as test_name,
    p.handle as player_name,
    p.ai_personality,
    s.credits,
    -- Check what decision the AI would make
    CASE p.ai_personality
        WHEN 'trader' THEN 'Should prioritize trading (but no ports in sector 1)'
        WHEN 'explorer' THEN 'Should prioritize exploration (move to other sectors)'
        WHEN 'warrior' THEN 'Should prioritize combat (but no enemies in sector 1)'
        WHEN 'colonizer' THEN 'Should prioritize planet claiming (but no planets in sector 1)'
        WHEN 'balanced' THEN 'Should do mixed actions (explore, trade, upgrade)'
        ELSE 'Unknown personality'
    END as expected_behavior,
    -- Check if they can afford basic actions
    CASE 
        WHEN s.credits >= 1000 THEN 'Can afford upgrades'
        ELSE 'Cannot afford upgrades'
    END as upgrade_affordability,
    -- Check cargo status
    CASE 
        WHEN s.ore > 0 OR s.organics > 0 OR s.goods > 0 THEN 'Has cargo to sell'
        ELSE 'No cargo to sell'
    END as cargo_status
FROM players p
JOIN ships s ON p.id = s.player_id
WHERE p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
AND p.is_ai = TRUE
ORDER BY p.handle
LIMIT 3;

-- Check what sectors are available for exploration
SELECT 
    'Available Sectors' as check_name,
    sec.number as sector_number,
    (SELECT COUNT(*) FROM ports WHERE sector_id = sec.id) as ports_count,
    (SELECT COUNT(*) FROM planets WHERE sector_id = sec.id AND owner_player_id IS NULL) as unclaimed_planets,
    (SELECT COUNT(*) FROM players p2 WHERE p2.current_sector = sec.id AND p2.is_ai = FALSE) as human_players
FROM sectors sec
WHERE sec.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
AND sec.number != 1  -- Exclude sector 1 where AI players are stuck
ORDER BY sec.number
LIMIT 10;
