-- Fix rankings system to use credits from ships table instead of players table
-- This fixes the "integer out of range" error in cron rankings updates
-- Combines fixes from sql_archive/141_fix_rankings_credits.sql with overflow protection

-- Update calculate_economic_score function to get credits from ships table
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
  -- Get ship credits (moved from players table)
  SELECT COALESCE(s.credits, 0) INTO v_credits
  FROM players p
  JOIN ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Calculate trading volume (sum of all trade values)
  -- Use BIGINT arithmetic to prevent overflow, then cap the result
  SELECT COALESCE(CAST(SUM(
    CASE 
      WHEN action = 'buy' THEN CAST(qty AS BIGINT) * price
      WHEN action = 'sell' THEN CAST(qty AS BIGINT) * price
      ELSE 0
    END
  ) AS INTEGER), 0) INTO v_trading_volume
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Calculate port influence (number of unique ports traded at)
  SELECT COUNT(DISTINCT port_id) INTO v_port_influence
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Economic score formula: credits + (trading_volume / 1000) + (port_influence * 100)
  -- Cap individual components to prevent integer overflow
  v_score := LEAST(v_credits, 2147483647) + 
             LEAST((LEAST(v_trading_volume, 2147483647) / 1000), 2147483647) + 
             LEAST((v_port_influence * 100), 2147483647);
  
  -- Ensure final score doesn't overflow
  RETURN GREATEST(0, LEAST(v_score, 2147483647));
END;
$$;

-- Update calculate_military_score function to add overflow protection
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
  -- Cap to prevent integer overflow
  v_score := LEAST(v_ship_levels, 2147483647) + LEAST((v_combat_victories * 500), 2147483647);
  
  RETURN GREATEST(0, LEAST(v_score, 2147483647));
END;
$$;

-- Update calculate_territorial_score function to add overflow protection
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
  -- Cap individual components to prevent integer overflow
  v_score := LEAST((v_planets_owned * 1000), 2147483647) + 
             LEAST((v_sectors_controlled * 500), 2147483647) + 
             LEAST(v_planet_development, 2147483647);
  
  RETURN GREATEST(0, LEAST(v_score, 2147483647));
END;
$$;

-- Update calculate_exploration_score function to add overflow protection
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
  -- Cap individual components to prevent integer overflow
  v_score := LEAST((v_sectors_visited * 50), 2147483647) + 
             LEAST(((v_sectors_visited * 1000) / GREATEST(1, v_universe_size)), 2147483647) + 
             LEAST(v_warp_discoveries, 2147483647);
  
  RETURN GREATEST(0, LEAST(v_score, 2147483647));
END;
$$;

-- Update calculate_total_score function to add overflow protection
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
  -- Use BIGINT arithmetic to prevent overflow, then cast back to INTEGER
  v_total := CAST(
    (CAST(v_economic AS BIGINT) * 0.40) + 
    (CAST(v_territorial AS BIGINT) * 0.25) + 
    (CAST(v_military AS BIGINT) * 0.20) + 
    (CAST(v_exploration AS BIGINT) * 0.15) 
    AS INTEGER
  );
  
  -- Cap final total to prevent overflow
  v_total := LEAST(v_total, 2147483647);
  
  RETURN json_build_object(
    'economic', v_economic,
    'territorial', v_territorial,
    'military', v_military,
    'exploration', v_exploration,
    'total', v_total
  );
END;
$$;
