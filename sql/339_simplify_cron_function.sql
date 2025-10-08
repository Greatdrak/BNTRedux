-- Simplify the cron function to directly use simple_ai_debug
-- This will eliminate the normalization issues

CREATE OR REPLACE FUNCTION public.cron_run_ai_actions_safe(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_lock_key bigint;
  v_got_lock boolean;
  v_result jsonb;
BEGIN
  v_lock_key := ('x' || substr(replace(p_universe_id::text, '-', ''), 1, 16))::bit(64)::bigint;
  v_got_lock := pg_try_advisory_lock(v_lock_key);

  IF NOT v_got_lock THEN
    RETURN jsonb_build_object('success', false, 'message', 'busy');
  END IF;

  BEGIN
    -- Use the simple debug function directly
    SELECT simple_ai_debug(p_universe_id) INTO v_result;
    
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_build_object(
      'success', false, 
      'message', SQLERRM,
      'ai_total', 0,
      'ai_with_turns', 0,
      'ai_with_goal', 0,
      'actions_taken', 0,
      'players_processed', 0,
      'planets_claimed', 0,
      'upgrades', 0,
      'trades', 0
    );
  END;

  PERFORM pg_advisory_unlock(v_lock_key);
  RETURN v_result;
END;
$$;
