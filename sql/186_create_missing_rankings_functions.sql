-- Create missing rankings functions that the API expects

-- Create player_rankings table if it doesn't exist
CREATE TABLE IF NOT EXISTS player_rankings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL,
  universe_id UUID NOT NULL,
  score INTEGER DEFAULT 0,
  economic_score INTEGER DEFAULT 0,
  territorial_score INTEGER DEFAULT 0,
  military_score INTEGER DEFAULT 0,
  exploration_score INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(player_id, universe_id)
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_player_rankings_universe_score ON player_rankings(universe_id, score DESC);
CREATE INDEX IF NOT EXISTS idx_player_rankings_player ON player_rankings(player_id);

-- Create get_leaderboard function
CREATE OR REPLACE FUNCTION get_leaderboard(
  p_universe_id UUID,
  p_limit INTEGER DEFAULT 50,
  p_ai_only BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
  rank BIGINT,
  player_id UUID,
  player_name TEXT,
  handle TEXT,
  score INTEGER,
  turns_spent INTEGER,
  last_login TIMESTAMPTZ,
  is_online BOOLEAN,
  is_ai BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH ranked_players AS (
    SELECT 
      p.id as player_id,
      p.player_name,
      p.handle,
      COALESCE(pr.score, 0) as score,
      p.turns_spent,
      p.last_login,
      p.is_online,
      p.is_ai,
      ROW_NUMBER() OVER (ORDER BY COALESCE(pr.score, 0) DESC, p.player_name ASC) as rank_num
    FROM players p
    LEFT JOIN player_rankings pr ON pr.player_id = p.id AND pr.universe_id = p.universe_id
    WHERE p.universe_id = p_universe_id
      AND (NOT p_ai_only OR p.is_ai = TRUE)
      AND (p_ai_only OR p.is_ai = FALSE)
  )
  SELECT 
    rp.rank_num::BIGINT as rank,
    rp.player_id,
    rp.player_name,
    rp.handle,
    rp.score,
    rp.turns_spent,
    rp.last_login,
    rp.is_online,
    rp.is_ai
  FROM ranked_players rp
  ORDER BY rp.rank_num
  LIMIT p_limit;
END;
$$;

-- Create update_universe_rankings function
CREATE OR REPLACE FUNCTION update_universe_rankings(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_score_json JSON;
  v_updated_count INTEGER := 0;
BEGIN
  -- Loop through all players in the universe and update their rankings
  FOR v_player IN 
    SELECT id FROM players WHERE universe_id = p_universe_id
  LOOP
    -- Calculate total score for this player
    v_score_json := calculate_total_score(v_player.id, p_universe_id);
    
    -- Insert or update player ranking
    INSERT INTO player_rankings (player_id, universe_id, score, economic_score, territorial_score, military_score, exploration_score, updated_at)
    VALUES (
      v_player.id,
      p_universe_id,
      (v_score_json->>'total')::INTEGER,
      (v_score_json->>'economic')::INTEGER,
      (v_score_json->>'territorial')::INTEGER,
      (v_score_json->>'military')::INTEGER,
      (v_score_json->>'exploration')::INTEGER,
      NOW()
    )
    ON CONFLICT (player_id, universe_id)
    DO UPDATE SET
      score = (v_score_json->>'total')::INTEGER,
      economic_score = (v_score_json->>'economic')::INTEGER,
      territorial_score = (v_score_json->>'territorial')::INTEGER,
      military_score = (v_score_json->>'military')::INTEGER,
      exploration_score = (v_score_json->>'exploration')::INTEGER,
      updated_at = NOW();
    
    v_updated_count := v_updated_count + 1;
  END LOOP;
  
  -- Update the universe settings to mark rankings as updated
  UPDATE universe_settings 
  SET last_rankings_generation_event = NOW()
  WHERE universe_id = p_universe_id;
  
  RETURN json_build_object(
    'ok', true,
    'message', 'Rankings updated successfully',
    'players_updated', v_updated_count,
    'universe_id', p_universe_id
  );
END;
$$;
