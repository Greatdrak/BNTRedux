-- Migration: 298_ai_debug_snapshot.sql
-- Purpose: Return a JSON snapshot to understand why AI may be idle

CREATE OR REPLACE FUNCTION public.get_ai_debug_snapshot(p_universe_id uuid)
RETURNS jsonb
LANGUAGE sql
AS $$
  WITH ai AS (
    SELECT id, handle, current_sector, turns, turns_spent
    FROM public.players
    WHERE universe_id = p_universe_id AND is_ai = TRUE
  ),
  mem AS (
    SELECT m.player_id, m.current_goal, m.target_sector_id
    FROM public.ai_player_memory m
    JOIN ai ON ai.id = m.player_id
  ),
  rec AS (
    SELECT COUNT(*) AS recent_actions,
           COUNT(DISTINCT player_id) AS recent_ai
    FROM public.ai_action_log
    WHERE universe_id = p_universe_id
      AND created_at >= now() - interval '1 hour'
  ),
  ports AS (
    SELECT COUNT(*) AS ports_count FROM public.ports p
    JOIN public.sectors s ON s.id = p.sector_id AND s.universe_id = p_universe_id
  ),
  sample AS (
    SELECT a.id, a.turns, a.turns_spent, a.current_sector,
           (SELECT jsonb_build_object('goal', m.current_goal, 'target_sector_id', m.target_sector_id, 'target_planet_id', NULL)
            FROM mem m WHERE m.player_id = a.id) AS memory
    FROM ai a
    ORDER BY a.id
    LIMIT 5
  )
  SELECT jsonb_build_object(
    'ai_players', (SELECT jsonb_build_object('count', COUNT(*)) FROM ai),
    'ports', (SELECT jsonb_build_object('count', ports_count) FROM ports),
    'recent', (SELECT jsonb_build_object('actions_last_hour', recent_actions, 'ai_last_hour', recent_ai) FROM rec),
    'sample_ai', (SELECT jsonb_agg(jsonb_build_object(
                    'player_id', id,
                    'turns', turns,
                    'turns_spent', turns_spent,
                    'current_sector', current_sector,
                    'memory', memory
                  )) FROM sample)
  );
$$;
