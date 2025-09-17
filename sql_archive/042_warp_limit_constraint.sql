-- Warp Limit Constraint
-- How to apply: Run once in Supabase SQL Editor
-- This enforces a maximum of 15 warps per universe (10 natural + 5 from warp editor)

-- Create a function to check warp count per universe
CREATE OR REPLACE FUNCTION check_warp_count()
RETURNS TRIGGER AS $$
DECLARE
  warp_count INTEGER;
BEGIN
  -- Count existing warps for this universe
  SELECT COUNT(*) INTO warp_count
  FROM warps
  WHERE universe_id = NEW.universe_id;
  
  -- Check if adding this warp would exceed the limit
  IF warp_count >= 15 THEN
    RAISE EXCEPTION 'Maximum warp limit reached: Universe % already has 15 warps', NEW.universe_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to enforce warp limit
DO $$
BEGIN
  -- Drop trigger if it exists
  DROP TRIGGER IF EXISTS warp_limit_trigger ON warps;
  
  -- Create the trigger
  CREATE TRIGGER warp_limit_trigger
    BEFORE INSERT ON warps
    FOR EACH ROW
    EXECUTE FUNCTION check_warp_count();
    
  RAISE NOTICE 'Warp limit trigger created: Maximum 15 warps per universe';
END $$;
