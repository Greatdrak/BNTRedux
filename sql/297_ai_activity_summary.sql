-- Migration: 297_ai_activity_summary.sql
-- Purpose: Provide a quick activity summary for dashboards

CREATE OR REPLACE FUNCTION public.get_ai_activity_summary(p_universe_id uuid, p_hours integer DEFAULT 24)
RETURNS jsonb
LANGUAGE sql
AS $$
  WITH recent AS (
    SELECT *
    FROM public.ai_action_log
    WHERE universe_id = p_universe_id
      AND created_at >= now() - make_interval(hours => GREATEST(1, p_hours))
  )
  SELECT jsonb_build_object(
    'since_hours', GREATEST(1, p_hours),
    'total_actions', COUNT(*),
    'players_involved', COUNT(DISTINCT player_id),
    'trades', COUNT(*) FILTER (WHERE action = 'trade'),
    'upgrades', COUNT(*) FILTER (WHERE action = 'upgrade'),
    'claims', COUNT(*) FILTER (WHERE action = 'claim_planet'),
    'moves', COUNT(*) FILTER (WHERE action = 'move' OR action = 'hyperspace'),
    'last_action_at', MAX(created_at)
  )
  FROM recent;
$$;
