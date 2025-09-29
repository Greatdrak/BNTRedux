-- Check what the actual game_trade function looks like in the database
SELECT 
  routine_name,
  routine_definition
FROM information_schema.routines 
WHERE routine_name = 'game_trade' 
  AND routine_schema = 'public';
