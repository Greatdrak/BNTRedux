-- Debug the universe destruction issue

-- Test 1: Check what universes exist and their names
SELECT 
    'Universe Check' as check_name,
    id,
    name,
    created_at
FROM universes 
ORDER BY created_at;

-- Test 2: Test the destroy_universe function with a specific universe
-- First, let's see what the function returns without actually destroying
CREATE OR REPLACE FUNCTION public.test_destroy_universe(p_universe_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_universe_name TEXT;
BEGIN
  -- Get universe name for logging (same as destroy function)
  SELECT name INTO v_universe_name FROM universes WHERE id = p_universe_id;
  
  IF v_universe_name IS NULL THEN
    RETURN jsonb_build_object('error', 'Universe not found');
  END IF;
  
  -- Return what we would return (without actually destroying)
  RETURN jsonb_build_object(
    'ok', true,
    'universe_name', v_universe_name,
    'message', 'Test successful - universe name found'
  );
END;
$$;

-- Test 3: Test with the Alpha universe
SELECT 'Test Alpha Universe' as test_name, 
       public.test_destroy_universe('34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID) as result;
