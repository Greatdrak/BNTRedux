-- Migration: 301_update_cron_ai_stats.sql
-- Purpose: Add readiness stats to cron_run_ai_actions_safe output for diagnostics

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
  v_ai_total int := 0;
  v_ai_with_goal int := 0;
  v_ai_with_turns int := 0;
BEGIN
  -- Pre-run readiness stats
  SELECT COUNT(*) INTO v_ai_total
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;

  SELECT COUNT(*) INTO v_ai_with_goal
  FROM public.players p
  JOIN public.ai_player_memory m ON m.player_id = p.id
  WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE AND m.current_goal IS NOT NULL;

  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE AND COALESCE(p.turns,0) > 0;

  v_result := v_result
    || jsonb_build_object('ai_total', v_ai_total, 'ai_with_goal', v_ai_with_goal, 'ai_with_turns', v_ai_with_turns);

  -- Create a lock key from universe_id
  v_lock_key := ('x' || substr(replace(p_universe_id::text, '-', ''), 1, 16))::bit(64)::bigint;
  v_got_lock := pg_try_advisory_lock(v_lock_key);

  IF NOT v_got_lock THEN
    RETURN v_result || jsonb_build_object('success', false, 'message', 'busy');
  END IF;

  BEGIN
    -- Call existing AI runner
    v_raw := COALESCE(
      (SELECT to_jsonb(x) FROM (SELECT * FROM run_ai_player_actions(p_universe_id)) x),
      jsonb_build_object('message', 'no_result')
    );

    -- Normalize fields
    v_result := v_result
      || jsonb_build_object('success', true)
      || jsonb_build_object('message', COALESCE(v_raw->>'message', 'ok'))
      || jsonb_build_object('actions_taken', COALESCE((v_raw->>'actions_taken')::int, (v_raw->>'total_actions')::int, 0))
      || jsonb_build_object('players_processed', COALESCE((v_raw->>'players_processed')::int, (v_raw->>'active_ai_players')::int, 0))
      || jsonb_build_object('planets_claimed', COALESCE((v_raw->>'planets_claimed')::int, 0))
      || jsonb_build_object('upgrades', COALESCE((v_raw->>'upgrades')::int, 0))
      || jsonb_build_object('trades', COALESCE((v_raw->>'trades')::int, 0));
  EXCEPTION WHEN OTHERS THEN
    v_result := v_result || jsonb_build_object('success', false, 'message', SQLERRM);
  END;

  PERFORM pg_advisory_unlock(v_lock_key);
  RETURN v_result;
END;
$$;
