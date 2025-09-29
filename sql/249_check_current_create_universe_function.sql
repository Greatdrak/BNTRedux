-- Check what the current create_universe function actually looks like
SELECT 
    routine_name,
    routine_definition
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name = 'create_universe'
AND routine_type = 'FUNCTION';
