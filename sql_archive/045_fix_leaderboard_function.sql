-- Fix the get_leaderboard function to use jsonb instead of json
-- This resolves the "operator does not exist: json || json" error

CREATE OR REPLACE FUNCTION get_leaderboard(p_universe_id UUID, p_limit INTEGER DEFAULT 50)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSONB := '[]'::jsonb;
  v_player RECORD;
  v_ai RECORD;
BEGIN
  -- Get top players
  FOR v_player IN 
    SELECT 
      pr.rank_position,
      p.handle,
      pr.total_score,
      pr.economic_score,
      pr.territorial_score,
      pr.military_score,
      pr.exploration_score,
      'player' as type
    FROM player_rankings pr
    JOIN players p ON pr.player_id = p.id
    WHERE pr.universe_id = p_universe_id
    ORDER BY pr.rank_position
    LIMIT p_limit
  LOOP
    v_result := v_result || jsonb_build_object(
      'rank', v_player.rank_position,
      'name', v_player.handle,
      'total_score', v_player.total_score,
      'economic_score', v_player.economic_score,
      'territorial_score', v_player.territorial_score,
      'military_score', v_player.military_score,
      'exploration_score', v_player.exploration_score,
      'type', v_player.type
    );
  END LOOP;
  
  -- Get AI players
  FOR v_ai IN 
    SELECT 
      ap.rank_position,
      ap.name,
      ap.total_score,
      ap.economic_score,
      ap.territorial_score,
      ap.military_score,
      ap.exploration_score,
      'ai' as type
    FROM ai_players ap
    WHERE ap.universe_id = p_universe_id
    ORDER BY ap.rank_position
  LOOP
    v_result := v_result || jsonb_build_object(
      'rank', v_ai.rank_position,
      'name', v_ai.name,
      'total_score', v_ai.total_score,
      'economic_score', v_ai.economic_score,
      'territorial_score', v_ai.territorial_score,
      'military_score', v_ai.military_score,
      'exploration_score', v_ai.exploration_score,
      'type', v_ai.type
    );
  END LOOP;
  
  -- Sort combined results by rank
  SELECT jsonb_agg(entry ORDER BY (entry->>'rank')::INTEGER)
  INTO v_result
  FROM jsonb_array_elements(v_result) as entry;
  
  RETURN json_build_object('ok', true, 'leaderboard', v_result);
END;
$$;
