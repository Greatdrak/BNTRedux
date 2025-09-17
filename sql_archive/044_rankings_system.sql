-- Rankings System for BNT Redux
-- How to apply: Run once in Supabase SQL Editor

-- Player Rankings Table
CREATE TABLE IF NOT EXISTS player_rankings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID REFERENCES players(id) ON DELETE CASCADE,
  universe_id UUID REFERENCES universes(id) ON DELETE CASCADE,
  economic_score INTEGER DEFAULT 0,
  territorial_score INTEGER DEFAULT 0,
  military_score INTEGER DEFAULT 0,
  exploration_score INTEGER DEFAULT 0,
  total_score INTEGER DEFAULT 0,
  rank_position INTEGER,
  last_updated TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(player_id, universe_id)
);

-- AI Players Table
CREATE TABLE IF NOT EXISTS ai_players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  universe_id UUID REFERENCES universes(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  ai_type TEXT CHECK (ai_type IN ('trader', 'explorer', 'military', 'balanced')) DEFAULT 'balanced',
  economic_score INTEGER DEFAULT 0,
  territorial_score INTEGER DEFAULT 0,
  military_score INTEGER DEFAULT 0,
  exploration_score INTEGER DEFAULT 0,
  total_score INTEGER DEFAULT 0,
  rank_position INTEGER,
  last_updated TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(name, universe_id)
);

-- Ranking History Table (for tracking changes over time)
CREATE TABLE IF NOT EXISTS ranking_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID REFERENCES players(id) ON DELETE CASCADE,
  universe_id UUID REFERENCES universes(id) ON DELETE CASCADE,
  rank_position INTEGER,
  total_score INTEGER,
  economic_score INTEGER,
  territorial_score INTEGER,
  military_score INTEGER,
  exploration_score INTEGER,
  recorded_at TIMESTAMP DEFAULT NOW()
);

-- AI Ranking History Table
CREATE TABLE IF NOT EXISTS ai_ranking_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ai_player_id UUID REFERENCES ai_players(id) ON DELETE CASCADE,
  universe_id UUID REFERENCES universes(id) ON DELETE CASCADE,
  rank_position INTEGER,
  total_score INTEGER,
  economic_score INTEGER,
  territorial_score INTEGER,
  military_score INTEGER,
  exploration_score INTEGER,
  recorded_at TIMESTAMP DEFAULT NOW()
);

-- Add AI player count to universes table
ALTER TABLE universes ADD COLUMN IF NOT EXISTS ai_player_count INTEGER DEFAULT 0;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_player_rankings_universe ON player_rankings(universe_id);
CREATE INDEX IF NOT EXISTS idx_player_rankings_position ON player_rankings(universe_id, rank_position);
CREATE INDEX IF NOT EXISTS idx_ai_players_universe ON ai_players(universe_id);
CREATE INDEX IF NOT EXISTS idx_ai_players_position ON ai_players(universe_id, rank_position);
CREATE INDEX IF NOT EXISTS idx_ranking_history_player ON ranking_history(player_id, universe_id);
CREATE INDEX IF NOT EXISTS idx_ranking_history_time ON ranking_history(recorded_at);

-- Function to calculate economic score for a player
CREATE OR REPLACE FUNCTION calculate_economic_score(p_player_id UUID, p_universe_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_score INTEGER := 0;
  v_credits INTEGER;
  v_trading_volume INTEGER;
  v_port_influence INTEGER;
BEGIN
  -- Get player credits
  SELECT COALESCE(credits, 0) INTO v_credits
  FROM players
  WHERE id = p_player_id AND universe_id = p_universe_id;
  
  -- Calculate trading volume (sum of all trade values)
  SELECT COALESCE(SUM(
    CASE 
      WHEN action = 'buy' THEN qty * price
      WHEN action = 'sell' THEN qty * price
      ELSE 0
    END
  ), 0) INTO v_trading_volume
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Calculate port influence (number of unique ports traded at)
  SELECT COUNT(DISTINCT port_id) INTO v_port_influence
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Economic score formula: credits + (trading_volume / 1000) + (port_influence * 100)
  v_score := v_credits + (v_trading_volume / 1000) + (v_port_influence * 100);
  
  RETURN GREATEST(0, v_score);
END;
$$;

-- Function to calculate territorial score for a player
CREATE OR REPLACE FUNCTION calculate_territorial_score(p_player_id UUID, p_universe_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_score INTEGER := 0;
  v_planets_owned INTEGER;
  v_planet_development INTEGER;
  v_sectors_controlled INTEGER;
BEGIN
  -- Count planets owned
  SELECT COUNT(*) INTO v_planets_owned
  FROM planets pl
  JOIN sectors s ON pl.sector_id = s.id
  WHERE pl.owner_player_id = p_player_id AND s.universe_id = p_universe_id;
  
  -- Calculate planet development (sum of planet levels/upgrades)
  -- For now, just count planets. Future: add planet upgrade levels
  v_planet_development := v_planets_owned * 100;
  
  -- Count unique sectors with owned planets
  SELECT COUNT(DISTINCT s.id) INTO v_sectors_controlled
  FROM planets pl
  JOIN sectors s ON pl.sector_id = s.id
  WHERE pl.owner_player_id = p_player_id AND s.universe_id = p_universe_id;
  
  -- Territorial score formula: (planets * 1000) + (sectors * 500) + development
  v_score := (v_planets_owned * 1000) + (v_sectors_controlled * 500) + v_planet_development;
  
  RETURN GREATEST(0, v_score);
END;
$$;

-- Function to calculate military score for a player
CREATE OR REPLACE FUNCTION calculate_military_score(p_player_id UUID, p_universe_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_score INTEGER := 0;
  v_ship_levels INTEGER;
  v_combat_victories INTEGER;
BEGIN
  -- Calculate ship level score (sum of all upgrade levels)
  SELECT COALESCE(
    (engine_lvl + comp_lvl + sensor_lvl + shield_lvl + hull_lvl) * 100, 
    0
  ) INTO v_ship_levels
  FROM ships s
  JOIN players p ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Future: Add combat victories when combat system is implemented
  v_combat_victories := 0;
  
  -- Military score formula: ship_levels + (combat_victories * 500)
  v_score := v_ship_levels + (v_combat_victories * 500);
  
  RETURN GREATEST(0, v_score);
END;
$$;

-- Function to calculate exploration score for a player
CREATE OR REPLACE FUNCTION calculate_exploration_score(p_player_id UUID, p_universe_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_score INTEGER := 0;
  v_sectors_visited INTEGER;
  v_warp_discoveries INTEGER;
  v_universe_size INTEGER;
BEGIN
  -- Count unique sectors visited
  SELECT COUNT(DISTINCT v.sector_id) INTO v_sectors_visited
  FROM visited v
  JOIN players p ON v.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Count warp connections discovered (future feature)
  v_warp_discoveries := 0;
  
  -- Get universe size for percentage calculation
  SELECT COUNT(*) INTO v_universe_size
  FROM sectors
  WHERE universe_id = p_universe_id;
  
  -- Exploration score formula: (sectors_visited * 50) + (percentage * 1000) + discoveries
  v_score := (v_sectors_visited * 50) + ((v_sectors_visited * 1000) / GREATEST(1, v_universe_size)) + v_warp_discoveries;
  
  RETURN GREATEST(0, v_score);
END;
$$;

-- Function to calculate total score for a player
CREATE OR REPLACE FUNCTION calculate_total_score(p_player_id UUID, p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_economic INTEGER;
  v_territorial INTEGER;
  v_military INTEGER;
  v_exploration INTEGER;
  v_total INTEGER;
BEGIN
  -- Calculate individual scores
  v_economic := calculate_economic_score(p_player_id, p_universe_id);
  v_territorial := calculate_territorial_score(p_player_id, p_universe_id);
  v_military := calculate_military_score(p_player_id, p_universe_id);
  v_exploration := calculate_exploration_score(p_player_id, p_universe_id);
  
  -- Calculate total with weights: Economic(40%), Territorial(25%), Military(20%), Exploration(15%)
  v_total := (v_economic * 0.40) + (v_territorial * 0.25) + (v_military * 0.20) + (v_exploration * 0.15);
  
  RETURN json_build_object(
    'economic', v_economic,
    'territorial', v_territorial,
    'military', v_military,
    'exploration', v_exploration,
    'total', v_total
  );
END;
$$;

-- Function to update all player rankings for a universe
CREATE OR REPLACE FUNCTION update_universe_rankings(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_scores JSON;
  v_rank_position INTEGER := 1;
  v_result JSON := '[]'::json;
BEGIN
  -- Update player rankings
  FOR v_player IN 
    SELECT p.id, p.handle
    FROM players p
    WHERE p.universe_id = p_universe_id
    ORDER BY p.created_at
  LOOP
    -- Calculate scores
    v_scores := calculate_total_score(v_player.id, p_universe_id);
    
    -- Upsert ranking
    INSERT INTO player_rankings (
      player_id, universe_id, 
      economic_score, territorial_score, military_score, exploration_score, total_score,
      last_updated
    )
    VALUES (
      v_player.id, p_universe_id,
      (v_scores->>'economic')::INTEGER,
      (v_scores->>'territorial')::INTEGER,
      (v_scores->>'military')::INTEGER,
      (v_scores->>'exploration')::INTEGER,
      (v_scores->>'total')::INTEGER,
      NOW()
    )
    ON CONFLICT (player_id, universe_id)
    DO UPDATE SET
      economic_score = (v_scores->>'economic')::INTEGER,
      territorial_score = (v_scores->>'territorial')::INTEGER,
      military_score = (v_scores->>'military')::INTEGER,
      exploration_score = (v_scores->>'exploration')::INTEGER,
      total_score = (v_scores->>'total')::INTEGER,
      last_updated = NOW();
  END LOOP;
  
  -- Update rank positions for players
  WITH ranked_players AS (
    SELECT 
      pr.id,
      pr.player_id,
      pr.total_score,
      ROW_NUMBER() OVER (ORDER BY pr.total_score DESC) as new_rank
    FROM player_rankings pr
    WHERE pr.universe_id = p_universe_id
  )
  UPDATE player_rankings pr
  SET rank_position = rp.new_rank
  FROM ranked_players rp
  WHERE pr.id = rp.id;
  
  -- Update rank positions for AI players
  WITH ranked_ai AS (
    SELECT 
      ap.id,
      ap.total_score,
      ROW_NUMBER() OVER (ORDER BY ap.total_score DESC) as new_rank
    FROM ai_players ap
    WHERE ap.universe_id = p_universe_id
  )
  UPDATE ai_players ap
  SET rank_position = ra.new_rank
  FROM ranked_ai ra
  WHERE ap.id = ra.id;
  
  -- Record ranking history
  INSERT INTO ranking_history (
    player_id, universe_id, rank_position, total_score,
    economic_score, territorial_score, military_score, exploration_score
  )
  SELECT 
    pr.player_id, pr.universe_id, pr.rank_position, pr.total_score,
    pr.economic_score, pr.territorial_score, pr.military_score, pr.exploration_score
  FROM player_rankings pr
  WHERE pr.universe_id = p_universe_id;
  
  -- Record AI ranking history
  INSERT INTO ai_ranking_history (
    ai_player_id, universe_id, rank_position, total_score,
    economic_score, territorial_score, military_score, exploration_score
  )
  SELECT 
    ap.id, ap.universe_id, ap.rank_position, ap.total_score,
    ap.economic_score, ap.territorial_score, ap.military_score, ap.exploration_score
  FROM ai_players ap
  WHERE ap.universe_id = p_universe_id;
  
  RETURN json_build_object('ok', true, 'message', 'Rankings updated successfully');
END;
$$;

-- Function to get leaderboard for a universe
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
