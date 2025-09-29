-- Check what player functions actually exist

-- Test 1: Check what game functions exist
SELECT 
    'Game Functions' as check_name,
    proname as function_name,
    proargnames as argument_names,
    proargtypes::regtype[] as argument_types
FROM pg_proc 
WHERE proname LIKE 'game_%'
ORDER BY proname;

-- Test 2: Check if the functions we're trying to call exist
SELECT 
    'Specific Functions Check' as check_name,
    proname as function_name,
    CASE 
        WHEN proname = 'game_planet_claim' THEN 'EXISTS'
        WHEN proname = 'game_trade' THEN 'EXISTS' 
        WHEN proname = 'game_ship_upgrade' THEN 'EXISTS'
        WHEN proname = 'game_move' THEN 'EXISTS'
        ELSE 'MISSING'
    END as status
FROM pg_proc 
WHERE proname IN ('game_planet_claim', 'game_trade', 'game_ship_upgrade', 'game_move')
ORDER BY proname;
