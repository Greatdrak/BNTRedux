-- Check the actual structure of key tables to see what columns exist

-- Check trades table structure
SELECT 'TRADES TABLE:' as info;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'trades'
ORDER BY ordinal_position;

-- Check combats table structure  
SELECT 'COMBATS TABLE:' as info;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'combats'
ORDER BY ordinal_position;

-- Check player_rankings table structure
SELECT 'PLAYER_RANKINGS TABLE:' as info;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'player_rankings'
ORDER BY ordinal_position;

-- Check ai_player_memory table structure
SELECT 'AI_PLAYER_MEMORY TABLE:' as info;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'ai_player_memory'
ORDER BY ordinal_position;
