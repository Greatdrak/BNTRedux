-- Migration: 356_update_leaderboard_functions.sql
-- Purpose: Update leaderboard functions to use stored score column

-- Update get_leaderboard to use stored score
CREATE OR REPLACE FUNCTION public.get_leaderboard(
  p_universe_id uuid,
  p_limit integer DEFAULT 50,
  p_ai_only boolean DEFAULT false
)
RETURNS TABLE(
  rank integer,
  player_id uuid,
  player_name text,
  handle text,
  score bigint,
  turns_spent bigint,
  last_login timestamp with time zone,
  is_online boolean,
  is_ai boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ROW_NUMBER() OVER (ORDER BY p.score DESC)::INTEGER as rank,
    p.id as player_id,
    p.handle as player_name,
    p.handle,
    COALESCE(p.score, 0) as score,
    COALESCE(p.turns_spent, 0) as turns_spent,
    p.last_login,
    (p.last_login IS NOT NULL AND p.last_login > NOW() - INTERVAL '30 minutes') as is_online,
    COALESCE(p.is_ai, FALSE) as is_ai
  FROM players p
  WHERE 
    p.universe_id = p_universe_id
    AND (p_ai_only = FALSE OR p.is_ai = TRUE)
    AND (p_ai_only = TRUE OR p.is_ai = FALSE OR p.is_ai IS NULL)
  ORDER BY p.score DESC
  LIMIT p_limit;
END;
$$;

-- Update update_universe_rankings to refresh all player scores
DROP FUNCTION IF EXISTS public.update_universe_rankings(uuid);

CREATE OR REPLACE FUNCTION public.update_universe_rankings(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated_count INTEGER := 0;
BEGIN
  -- Refresh all player scores in the universe
  UPDATE public.players
  SET score = calculate_player_score(id)
  WHERE universe_id = p_universe_id;
  
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Rankings updated',
    'players_updated', v_updated_count
  );
END;
$$;

