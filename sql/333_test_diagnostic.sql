-- Test the diagnostic function
-- This will help us see what the diagnostic function returns

CREATE OR REPLACE FUNCTION public.test_diagnostic()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Test with the universe ID we've been using
  SELECT diagnose_ai_players('3c491d51-61e2-4969-ba3e-142d4f5747d8') INTO v_result;
  RETURN v_result;
END;
$$;
