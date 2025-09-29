-- Check if there are ANY AI players in the entire database

-- Count total AI players across all universes
SELECT 
    'Total AI Players' as check_name,
    COUNT(*) as count
FROM players 
WHERE is_ai = TRUE;

-- Show all AI players with their universe info
SELECT 
    'All AI Players' as check_name,
    p.id as player_id,
    p.handle as player_name,
    p.is_ai,
    p.ai_personality,
    u.name as universe_name,
    u.id as universe_id,
    s.credits,
    sec.number as sector_number
FROM players p
JOIN universes u ON p.universe_id = u.id
JOIN ships s ON p.id = s.player_id
JOIN sectors sec ON p.current_sector = sec.id
WHERE p.is_ai = TRUE
ORDER BY u.name, p.handle;

-- Check if AI players exist but are in wrong universe
SELECT 
    'AI Players by Universe' as check_name,
    u.name as universe_name,
    u.id as universe_id,
    COUNT(p.id) as ai_count
FROM universes u
LEFT JOIN players p ON u.id = p.universe_id AND p.is_ai = TRUE
GROUP BY u.id, u.name
ORDER BY ai_count DESC;
