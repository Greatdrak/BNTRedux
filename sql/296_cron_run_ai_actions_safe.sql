-- Migration: 296_cron_run_ai_actions_safe.sql
-- Purpose: Serialize AI runs per-universe and return normalized stats

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
  -- Create a lock key from universe_id
  v_lock_key := ('x' || substr(replace(p_universe_id::text, '-', ''), 1, 16))::bit(64)::bigint;
  v_got_lock := pg_try_advisory_lock(v_lock_key);

  IF NOT v_got_lock THEN
    RETURN jsonb_build_object('success', false, 'message', 'busy');
  END IF;

  BEGIN
    -- Call existing AI runner (assumed to be run_ai_player_actions)
    v_raw := COALESCE(
      (SELECT to_jsonb(x) FROM (SELECT * FROM run_ai_player_actions(p_universe_id)) x),
      jsonb_build_object('message', 'no_result')
    );

    -- Normalize fields if present in various shapes
    v_result := v_result
      || jsonb_build_object('success', true)
      || jsonb_build_object('message', COALESCE(v_raw->>'message', 'ok'))
      || jsonb_build_object('actions_taken', COALESCE((v_raw->>'actions_taken')::int, (v_raw->>'total_actions')::int, 0))
      || jsonb_build_object('players_processed', COALESCE((v_raw->>'players_processed')::int, (v_raw->>'active_ai_players')::int, 0))
      || jsonb_build_object('planets_claimed', COALESCE((v_raw->>'planets_claimed')::int, 0))
      || jsonb_build_object('upgrades', COALESCE((v_raw->>'upgrades')::int, 0))
      || jsonb_build_object('trades', COALESCE((v_raw->>'trades')::int, 0));
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_build_object('success', false, 'message', SQLERRM);
  END;

  PERFORM pg_advisory_unlock(v_lock_key);
  RETURN v_result;
END;
$$;
