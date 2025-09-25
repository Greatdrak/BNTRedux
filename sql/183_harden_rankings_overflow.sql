-- Harden rankings functions to avoid integer overflows by:
-- - Using BIGINT for intermediate arithmetic
-- - Applying LEAST caps before casting down to INTEGER
-- - Fetching credits from ships and capping safely

-- Economic score
CREATE OR REPLACE FUNCTION calculate_economic_score(p_player_id UUID, p_universe_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_score_big BIGINT := 0;
  v_credits_big BIGINT := 0;
  v_planet_credits_big BIGINT := 0;
  v_trading_volume_big BIGINT := 0;
  v_port_influence INT := 0;
BEGIN
  -- Ship credits (no cap here; we will dampen below)
  SELECT COALESCE(COALESCE(s.credits, 0), 0)::BIGINT
  INTO v_credits_big
  FROM players p
  JOIN ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  -- Sum of owned planet credits (banked)
  SELECT COALESCE(SUM(pl.credits), 0)::BIGINT
  INTO v_planet_credits_big
  FROM planets pl
  JOIN sectors sx ON pl.sector_id = sx.id
  WHERE pl.owner_player_id = p_player_id AND sx.universe_id = p_universe_id;

  -- Total trading volume (buy/sell qty * price) as BIGINT
  SELECT COALESCE(SUM(
    CASE 
      WHEN action = 'buy' THEN (qty::BIGINT) * (price::BIGINT)
      WHEN action = 'sell' THEN (qty::BIGINT) * (price::BIGINT)
      ELSE 0
    END
  ), 0)
  INTO v_trading_volume_big
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  -- Unique ports traded at
  SELECT COUNT(DISTINCT port_id) INTO v_port_influence
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  -- Economic score emphasizing assets with a Credits->Score ratio of ~1:0.000001
  -- so 10,000,000,000 credits ~ 10,000 score before category weighting.
  --   credits_term = (ship_credits + planet_credits) / 100000
  --   trade_term   = trade_volume / 10000000
  --   ports_term   = ports_traded * 1
  v_score_big := LEAST(((GREATEST(0, v_credits_big + v_planet_credits_big)) / 100000), 2147483647)
                  + LEAST((v_trading_volume_big / 10000000), 2147483647)
                  + LEAST((v_port_influence::BIGINT * 1), 2147483647);

  RETURN GREATEST(0, LEAST(v_score_big, 2147483647))::INTEGER;
END;
$$;

-- Military score
CREATE OR REPLACE FUNCTION calculate_military_score(p_player_id UUID, p_universe_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_score_big BIGINT := 0;
  v_ship_levels_big BIGINT := 0;
  v_combat_victories INT := 0;
BEGIN
  -- Sum of ship upgrade levels * 100
  SELECT COALESCE(((s.engine_lvl + s.comp_lvl + s.sensor_lvl + s.shield_lvl + s.hull_lvl)::BIGINT * 100), 0)
  INTO v_ship_levels_big
  FROM ships s
  JOIN players p ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  -- Placeholder for future victories
  v_combat_victories := 0;

  v_score_big := LEAST(v_ship_levels_big, 2147483647) 
                  + LEAST((v_combat_victories::BIGINT * 500), 2147483647);

  RETURN GREATEST(0, LEAST(v_score_big, 2147483647))::INTEGER;
END;
$$;

-- Territorial score
CREATE OR REPLACE FUNCTION calculate_territorial_score(p_player_id UUID, p_universe_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_score_big BIGINT := 0;
  v_planets_owned INT := 0;
  v_planet_development_big BIGINT := 0;
  v_sectors_controlled INT := 0;
BEGIN
  SELECT COUNT(*) INTO v_planets_owned
  FROM planets pl
  JOIN sectors s ON pl.sector_id = s.id
  WHERE pl.owner_player_id = p_player_id AND s.universe_id = p_universe_id;

  -- Simple development metric for now
  v_planet_development_big := (v_planets_owned::BIGINT * 100);

  SELECT COUNT(DISTINCT s.id) INTO v_sectors_controlled
  FROM planets pl
  JOIN sectors s ON pl.sector_id = s.id
  WHERE pl.owner_player_id = p_player_id AND s.universe_id = p_universe_id;

  v_score_big := LEAST((v_planets_owned::BIGINT * 1000), 2147483647)
                  + LEAST((v_sectors_controlled::BIGINT * 500), 2147483647)
                  + LEAST(v_planet_development_big, 2147483647);

  RETURN GREATEST(0, LEAST(v_score_big, 2147483647))::INTEGER;
END;
$$;

-- Exploration score
CREATE OR REPLACE FUNCTION calculate_exploration_score(p_player_id UUID, p_universe_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_score_big BIGINT := 0;
  v_sectors_visited INT := 0;
  v_warp_discoveries INT := 0;
  v_universe_size INT := 0;
BEGIN
  SELECT COUNT(DISTINCT v.sector_id) INTO v_sectors_visited
  FROM visited v
  JOIN players p ON v.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  v_warp_discoveries := 0; -- placeholder

  SELECT COUNT(*) INTO v_universe_size
  FROM sectors
  WHERE universe_id = p_universe_id;

  v_score_big := LEAST((v_sectors_visited::BIGINT * 50), 2147483647)
                  + LEAST(((v_sectors_visited::BIGINT * 1000) / GREATEST(1, v_universe_size)), 2147483647)
                  + LEAST(v_warp_discoveries::BIGINT, 2147483647);

  RETURN GREATEST(0, LEAST(v_score_big, 2147483647))::INTEGER;
END;
$$;

-- Total score
CREATE OR REPLACE FUNCTION calculate_total_score(p_player_id UUID, p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_economic INT;
  v_territorial INT;
  v_military INT;
  v_exploration INT;
  v_total_big BIGINT;
BEGIN
  v_economic := calculate_economic_score(p_player_id, p_universe_id);
  v_territorial := calculate_territorial_score(p_player_id, p_universe_id);
  v_military := calculate_military_score(p_player_id, p_universe_id);
  v_exploration := calculate_exploration_score(p_player_id, p_universe_id);

  v_total_big := (v_economic::BIGINT * 40) 
                  + (v_territorial::BIGINT * 25) 
                  + (v_military::BIGINT * 20) 
                  + (v_exploration::BIGINT * 15);
  -- divide by 100 using BIGINT math
  v_total_big := v_total_big / 100;

  RETURN json_build_object(
    'economic', v_economic,
    'territorial', v_territorial,
    'military', v_military,
    'exploration', v_exploration,
    'total', GREATEST(0, LEAST(v_total_big, 2147483647))::INTEGER
  );
END;
$$;


