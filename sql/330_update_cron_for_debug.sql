-- Update cron function to use debug version temporarily
-- This will help us see what's happening with AI processing

CREATE OR REPLACE FUNCTION public.cron_run_ai_actions_safe(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_lock_key bigint;
  v_got_lock boolean;
  v_result jsonb := jsonb_build_object(
    'success', false,
    'actions_taken', 0,
    'players_processed', 0,
    'planets_claimed', 0,
    'upgrades', 0,
    'trades', 0,
    'message', 'not_run'
  );
  v_raw jsonb;
BEGIN
  v_lock_key := ('x' || substr(replace(p_universe_id::text, '-', ''), 1, 16))::bit(64)::bigint;
  v_got_lock := pg_try_advisory_lock(v_lock_key);

  IF NOT v_got_lock THEN
    RETURN jsonb_build_object('success', false, 'message', 'busy');
  END IF;

  BEGIN
    -- Use the debug version to get detailed logging
    v_raw := COALESCE(
      (SELECT to_jsonb(x) FROM (SELECT * FROM run_ai_player_actions_debug(p_universe_id)) x),
      jsonb_build_object('message', 'no_result')
    );
    
    -- Normalize the result to match expected format
    v_result := jsonb_build_object(
      'success', COALESCE((v_raw->>'success')::boolean, false),
      'message', COALESCE(v_raw->>'message', 'ok'),
      'actions_taken', COALESCE((v_raw->>'actions_taken')::int, 0),
      'players_processed', COALESCE((v_raw->>'players_processed')::int, 0),
      'planets_claimed', COALESCE((v_raw->>'planets_claimed')::int, 0),
      'upgrades', COALESCE((v_raw->>'upgrades')::int, 0),
      'trades', COALESCE((v_raw->>'trades')::int, 0),
      'ai_total', COALESCE((v_raw->>'ai_total')::int, 0),
      'ai_with_turns', COALESCE((v_raw->>'ai_with_turns')::int, 0),
      'ai_with_goal', COALESCE((v_raw->>'ai_with_goal')::int, 0)
    );
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_build_object('success', false, 'message', SQLERRM);
  END;

  PERFORM pg_advisory_unlock(v_lock_key);
  RETURN v_result;
END;
$$;
