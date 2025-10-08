-- Get the full definition of both game_ship_upgrade functions
SELECT 
    pg_get_function_arguments(p.oid) AS arguments,
    pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
  AND p.proname = 'game_ship_upgrade'
ORDER BY pg_get_function_arguments(p.oid);




