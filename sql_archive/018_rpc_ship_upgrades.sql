-- Ship Upgrade RPC Functions
-- Handles ship upgrades and renaming with special port requirements

-- Ship upgrade function
CREATE OR REPLACE FUNCTION game_ship_upgrade(p_user_id UUID, p_attr TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_port RECORD;
  v_cost INTEGER;
  v_result JSONB;
BEGIN
  -- Get player data
  SELECT p.* INTO v_player
  FROM players p
  WHERE p.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship data
  SELECT s.* INTO v_ship
  FROM ships s
  WHERE s.player_id = v_player.id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  -- Check if player is at a special port
  SELECT * INTO v_port
  FROM ports
  WHERE sector_id = v_player.current_sector AND kind = 'special';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'port_not_special', 'message', 'Upgrades are only available at Special ports.'));
  END IF;

  -- Validate attribute
  IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
  END IF;

  -- Calculate cost based on attribute
  CASE p_attr
    WHEN 'engine' THEN
      v_cost := 500 * (v_ship.engine_lvl + 1);
    WHEN 'computer' THEN
      v_cost := 400 * (v_ship.comp_lvl + 1);
    WHEN 'sensors' THEN
      v_cost := 400 * (v_ship.sensor_lvl + 1);
    WHEN 'shields' THEN
      v_cost := 300 * (v_ship.shield_lvl + 1);
    WHEN 'hull' THEN
      v_cost := 2000 * (v_ship.hull_lvl + 1);
  END CASE;

  -- Check if player has enough credits
  IF v_player.credits < v_cost THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Insufficient credits for upgrade'));
  END IF;

  -- Apply upgrade
  CASE p_attr
    WHEN 'engine' THEN
      UPDATE ships SET engine_lvl = engine_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'computer' THEN
      UPDATE ships SET comp_lvl = comp_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'sensors' THEN
      UPDATE ships SET sensor_lvl = sensor_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'shields' THEN
      UPDATE ships SET shield_lvl = shield_lvl + 1 WHERE player_id = v_player.id;
      UPDATE ships SET shield = shield_max WHERE player_id = v_player.id;
    WHEN 'hull' THEN
      UPDATE ships SET hull_lvl = hull_lvl + 1 WHERE player_id = v_player.id;
      UPDATE ships SET hull = hull_max WHERE player_id = v_player.id;
      -- Force regeneration of generated columns
      UPDATE ships SET fighters = fighters WHERE player_id = v_player.id;
  END CASE;

  -- Deduct credits
  UPDATE players SET credits = credits - v_cost WHERE id = v_player.id;

  -- Get updated ship data
  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;

  -- Return success with updated data
  RETURN jsonb_build_object(
    'ok', true,
    'credits', v_player.credits - v_cost,
    'ship', jsonb_build_object(
      'name', v_ship.name,
      'hull', v_ship.hull,
      'hull_max', v_ship.hull_max,
      'hull_lvl', v_ship.hull_lvl,
      'shield', v_ship.shield,
      'shield_max', v_ship.shield_max,
      'shield_lvl', v_ship.shield_lvl,
      'engine_lvl', v_ship.engine_lvl,
      'comp_lvl', v_ship.comp_lvl,
      'sensor_lvl', v_ship.sensor_lvl,
      'cargo', v_ship.cargo,
      'fighters', v_ship.fighters,
      'torpedoes', v_ship.torpedoes
    )
  );
END;
$$;

-- Ship rename function
CREATE OR REPLACE FUNCTION game_ship_rename(p_user_id UUID, p_name TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_clean_name TEXT;
BEGIN
  -- Get player data
  SELECT p.* INTO v_player
  FROM players p
  WHERE p.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship data
  SELECT s.* INTO v_ship
  FROM ships s
  WHERE s.player_id = v_player.id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  -- Sanitize and validate name
  v_clean_name := TRIM(p_name);
  
  IF LENGTH(v_clean_name) = 0 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_name', 'message', 'Ship name cannot be empty'));
  END IF;

  IF LENGTH(v_clean_name) > 32 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_name', 'message', 'Ship name must be 32 characters or less'));
  END IF;

  -- Update ship name
  UPDATE ships SET name = v_clean_name WHERE player_id = v_player.id;

  -- Return success
  RETURN jsonb_build_object(
    'ok', true,
    'name', v_clean_name
  );
END;
$$;
