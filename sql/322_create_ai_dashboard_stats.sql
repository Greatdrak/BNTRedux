-- Migration: 322_create_ai_dashboard_stats.sql
-- Purpose: Create function to get accurate AI dashboard statistics

CREATE OR REPLACE FUNCTION public.get_ai_dashboard_stats(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_stats jsonb;
  v_total_ai int;
  v_active_ai int;
  v_actions_last_hour int;
  v_avg_credits numeric;
  v_total_planets int;
  v_personality_dist jsonb;
BEGIN
  -- Get total AI players
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players
  WHERE universe_id = p_universe_id AND is_ai = true;

  -- Get active AI (with turns > 0)
  SELECT COUNT(*) INTO v_active_ai
  FROM public.players
  WHERE universe_id = p_universe_id AND is_ai = true AND turns > 0;

  -- Get actions in last hour
  SELECT COUNT(*) INTO v_actions_last_hour
  FROM public.ai_action_log
  WHERE universe_id = p_universe_id 
    AND created_at > NOW() - INTERVAL '1 hour'
    AND outcome = 'success';

  -- Get average credits
  SELECT COALESCE(AVG(s.credits), 0) INTO v_avg_credits
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;

  -- Get total AI-owned planets
  SELECT COUNT(*) INTO v_total_planets
  FROM public.planets pl
  JOIN public.players p ON p.id = pl.owner_player_id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;

  -- Get personality distribution
  SELECT jsonb_object_agg(
    COALESCE(ai_personality::text, 'unknown'), 
    count
  ) INTO v_personality_dist
  FROM (
    SELECT ai_personality, COUNT(*) as count
    FROM public.players
    WHERE universe_id = p_universe_id AND is_ai = true
    GROUP BY ai_personality
  ) sub;

  -- Build result
  v_stats := jsonb_build_object(
    'total_ai_players', v_total_ai,
    'active_ai_players', v_active_ai,
    'actions_last_hour', v_actions_last_hour,
    'average_credits', ROUND(v_avg_credits),
    'total_ai_planets', v_total_planets,
    'personality_distribution', COALESCE(v_personality_dist, '{}'::jsonb)
  );

  RETURN v_stats;
END;
$$;
