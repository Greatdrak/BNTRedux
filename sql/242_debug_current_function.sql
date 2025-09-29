-- Debug: Check what the current destroy_universe function actually looks like
-- This will show us if the migration was applied correctly

SELECT 
    routine_name,
    routine_definition
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name = 'destroy_universe'
AND routine_type = 'FUNCTION';
