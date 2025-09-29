-- Simple AI System Diagnostic - Check each component individually

-- 1. Check if AI players exist
SELECT 
    'AI Players Exist' as check_name,
    COUNT(*) as count,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM players 
WHERE is_ai = TRUE;

-- 2. Check AI players with personalities
SELECT 
    'AI Players with Personalities' as check_name,
    COUNT(*) as count,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM players 
WHERE is_ai = TRUE AND ai_personality IS NOT NULL;

-- 3. Check AI players with memory
SELECT 
    'AI Players with Memory' as check_name,
    COUNT(*) as count,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM players p
WHERE p.is_ai = TRUE 
AND p.id IN (SELECT player_id FROM ai_player_memory);

-- 4. Check if enhanced AI function exists
SELECT 
    'Enhanced AI Function Exists' as check_name,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'run_enhanced_ai_actions') 
         THEN 'PASS' ELSE 'FAIL' END as status;

-- 5. Check if cron function exists
SELECT 
    'Cron AI Function Exists' as check_name,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cron_run_ai_actions') 
         THEN 'PASS' ELSE 'FAIL' END as status;

-- 6. Check if AI decision function exists
SELECT 
    'AI Decision Function Exists' as check_name,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ai_make_decision') 
         THEN 'PASS' ELSE 'FAIL' END as status;

-- 7. Check if AI ship upgrade function exists
SELECT 
    'AI Ship Upgrade Function Exists' as check_name,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ai_ship_upgrade') 
         THEN 'PASS' ELSE 'FAIL' END as status;
