-- Test the actual destroy_universe function response format

-- Test 1: Check the exact response format from destroy_universe
CREATE OR REPLACE FUNCTION public.test_destroy_response_format()
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_universe_name TEXT := 'Test Universe';
  v_player_count INTEGER := 5;
  v_ship_count INTEGER := 5;
BEGIN
  -- Return the exact same format as destroy_universe
  RETURN jsonb_build_object(
    'ok', true,
    'universe_name', v_universe_name,
    'players_deleted', v_player_count,
    'ships_deleted', v_ship_count,
    'sectors_deleted', 100,
    'planets_deleted', 50,
    'ports_deleted', 25,
    'message', 'Universe destroyed successfully with all associated data'
  );
END;
$$;

-- Test 2: Check the response format
SELECT 'Response Format Test' as test_name, 
       public.test_destroy_response_format() as result;

-- Test 3: Check if there are any issues with the current destroy_universe function
-- Let's see what it would return for a non-existent universe
SELECT 'Non-existent Universe Test' as test_name,
       public.destroy_universe('00000000-0000-0000-0000-000000000000'::UUID) as result;
