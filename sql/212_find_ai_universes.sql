-- Find which universes actually have AI players

-- Check all universes and their AI player counts
SELECT 
    u.id as universe_id,
    u.name as universe_name,
    COUNT(p.id) as ai_player_count
FROM universes u
LEFT JOIN players p ON u.id = p.universe_id AND p.is_ai = TRUE
GROUP BY u.id, u.name
ORDER BY ai_player_count DESC;

-- Check the specific universe we've been testing
SELECT 
    'Test Universe Status' as check_name,
    u.id as universe_id,
    u.name as universe_name,
    COUNT(p.id) as total_players,
    COUNT(CASE WHEN p.is_ai = TRUE THEN 1 END) as ai_players,
    COUNT(CASE WHEN p.is_ai = FALSE THEN 1 END) as human_players
FROM universes u
LEFT JOIN players p ON u.id = p.universe_id
WHERE u.id = '16b343e6-0f4c-41ff-8ae5-107bfa104efb'::UUID
GROUP BY u.id, u.name;
