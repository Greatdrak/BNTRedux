-- Ultra Simple AI Check - Just see what exists

-- Check if there are ANY AI players at all
SELECT 'AI Players Count' as check_name, COUNT(*) as result FROM players WHERE is_ai = TRUE;

-- Check if there are ANY players at all
SELECT 'Total Players Count' as check_name, COUNT(*) as result FROM players;

-- Check if ai_personality column exists
SELECT 'AI Personality Column Exists' as check_name, 
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns 
                        WHERE table_name = 'players' AND column_name = 'ai_personality') 
            THEN 'YES' ELSE 'NO' END as result;

-- Check if ai_player_memory table exists
SELECT 'AI Memory Table Exists' as check_name,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables 
                        WHERE table_name = 'ai_player_memory') 
            THEN 'YES' ELSE 'NO' END as result;

-- Check what functions exist with 'ai' in the name
SELECT 'AI Functions' as check_name, proname as result 
FROM pg_proc 
WHERE proname LIKE '%ai%' 
ORDER BY proname;
