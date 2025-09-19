-- Test the port regeneration function to see what's causing the integer overflow
-- This will help us debug the issue

BEGIN;

-- Test the function with a specific universe
DO $$
DECLARE
  test_universe_id uuid;
  result RECORD;
BEGIN
  -- Get the first universe ID for testing
  SELECT id INTO test_universe_id FROM universes LIMIT 1;
  
  IF test_universe_id IS NULL THEN
    RAISE NOTICE 'No universes found for testing';
    RETURN;
  END IF;
  
  RAISE NOTICE 'Testing port regeneration for universe: %', test_universe_id;
  
  -- Call the function and capture the result
  SELECT * INTO result FROM update_port_stock_dynamics(test_universe_id);
  
  RAISE NOTICE 'Result: ports_updated=%, total_stock_changes=%', result.ports_updated, result.total_stock_changes;
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error: %', SQLERRM;
END $$;

COMMIT;
