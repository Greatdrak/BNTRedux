-- Migration: 354_update_get_ai_players.sql
-- Purpose: Update get_ai_players to include score and turns

DROP FUNCTION IF EXISTS public.get_ai_players(uuid);

CREATE OR REPLACE FUNCTION public.get_ai_players(p_universe_id uuid)
RETURNS TABLE(
  player_id uuid,
  player_name text,
  ship_id uuid,
  sector_number int,
  credits bigint,
  ai_personality text,
  score bigint,
  turns int,
  owned_planets bigint,
  ship_levels jsonb,
  last_action text,
  current_goal text
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id as player_id,
    p.handle as player_name,
    s.id as ship_id,
    sec.number as sector_number,
    s.credits,
    p.ai_personality::text,
    -- Read score from players table
    COALESCE(p.score, 0) as score,
    COALESCE(p.turns, 0) as turns,
    -- Count actual planets owned by this AI player
    COALESCE(planet_counts.planet_count, 0) as owned_planets,
    -- Ship levels as JSON
    jsonb_build_object(
      'hull', s.hull_lvl,
      'engine', s.engine_lvl,
      'power', COALESCE(s.power_lvl, 0),
      'computer', s.comp_lvl,
      'sensors', s.sensor_lvl,
      'beam_weapon', COALESCE(s.beam_lvl, 0),
      'armor', 0,
      'cloak', COALESCE(s.cloak_lvl, 0),
      'torp_launcher', COALESCE(s.torp_launcher_lvl, 0),
      'shield', s.shield_lvl
    ) as ship_levels,
    -- Get last action from ai_action_log
    (SELECT aal.action FROM ai_action_log aal
     WHERE aal.player_id = p.id 
     ORDER BY aal.created_at DESC 
     LIMIT 1) as last_action,
    -- Get current goal from ai_player_memory
    COALESCE(m.current_goal, 'explore') as current_goal
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  JOIN public.sectors sec ON sec.id = p.current_sector
  LEFT JOIN public.ai_player_memory m ON m.player_id = p.id
  LEFT JOIN (
    -- Count planets owned by each AI player
    SELECT 
      pl.owner_player_id,
      COUNT(*) as planet_count
    FROM public.planets pl
    JOIN public.players p2 ON p2.id = pl.owner_player_id
    WHERE p2.universe_id = p_universe_id 
      AND p2.is_ai = true
    GROUP BY pl.owner_player_id
  ) planet_counts ON planet_counts.owner_player_id = p.id
  WHERE p.universe_id = p_universe_id 
    AND p.is_ai = true
  ORDER BY p.score DESC NULLS LAST, p.handle;
END;
$$;

