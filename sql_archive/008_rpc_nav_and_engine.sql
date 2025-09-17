-- Hyperspace and Engine Upgrade RPCs
-- How to apply: Run once in Supabase SQL Editor after 007

-- Hyperspace jump by sector number with engine-based turn cost
CREATE OR REPLACE FUNCTION game_hyperspace(
  p_user_id UUID,
  p_target_sector_number INT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID;
  v_turns INT;
  v_current_sector_id UUID;
  v_current_number INT;
  v_target_sector_id UUID;
  v_engine_lvl INT;
  v_cost INT;
BEGIN
  -- Load player, current sector, ship
  SELECT p.id, p.turns, p.current_sector
  INTO v_player_id, v_turns, v_current_sector_id
  FROM players p WHERE p.user_id = p_user_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  SELECT s.number INTO v_current_number FROM sectors s WHERE s.id = v_current_sector_id;

  SELECT s.id INTO v_target_sector_id FROM sectors s
  JOIN universes u ON u.id = s.universe_id AND u.name = 'Alpha'
  WHERE s.number = p_target_sector_number;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','invalid_target','message','Target sector not found'));
  END IF;

  SELECT engine_lvl INTO v_engine_lvl FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  v_cost := GREATEST(1, CEIL( abs(v_current_number - p_target_sector_number)::NUMERIC / GREATEST(1, v_engine_lvl) )::INT);
  IF v_turns < v_cost THEN
    RETURN json_build_object('error', json_build_object('code','insufficient_turns','message','Not enough turns'));
  END IF;

  UPDATE players SET current_sector = v_target_sector_id, turns = turns - v_cost WHERE id = v_player_id;

  -- Upsert visited
  INSERT INTO visited (player_id, sector_id, first_seen, last_seen)
  VALUES (v_player_id, v_target_sector_id, now(), now())
  ON CONFLICT (player_id, sector_id) DO UPDATE SET last_seen = EXCLUDED.last_seen;

  SELECT turns INTO v_turns FROM players WHERE id = v_player_id;

  RETURN json_build_object('ok', true, 'player', json_build_object('current_sector_number', p_target_sector_number, 'turns', v_turns));
END; $$;

-- Engine upgrade (+1 level, linear cost)
CREATE OR REPLACE FUNCTION game_engine_upgrade(
  p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID;
  v_credits BIGINT;
  v_engine_lvl INT;
  v_cost INT;
BEGIN
  SELECT p.id, p.credits INTO v_player_id, v_credits FROM players p WHERE p.user_id = p_user_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  SELECT engine_lvl INTO v_engine_lvl FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  v_cost := 500 * (v_engine_lvl + 1);
  IF v_credits < v_cost THEN
    RETURN json_build_object('error', json_build_object('code','insufficient_funds','message','Insufficient credits'));
  END IF;

  UPDATE players SET credits = credits - v_cost WHERE id = v_player_id;
  UPDATE ships SET engine_lvl = engine_lvl + 1 WHERE player_id = v_player_id;

  SELECT p.credits, s.engine_lvl INTO v_credits, v_engine_lvl
  FROM players p JOIN ships s ON s.player_id = p.id
  WHERE p.id = v_player_id;

  RETURN json_build_object('ok', true, 'credits', v_credits, 'ship', json_build_object('engine_lvl', v_engine_lvl));
END; $$;


