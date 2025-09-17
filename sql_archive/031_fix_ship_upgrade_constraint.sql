-- Fix ship upgrade constraint violation
-- The issue was trying to reference generated columns in the same UPDATE statement

-- Drop and recreate the game_ship_upgrade function with proper hull/shield handling
DROP FUNCTION IF EXISTS game_ship_upgrade(uuid, text);

CREATE OR REPLACE FUNCTION game_ship_upgrade(p_user_id uuid, p_attr text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players%ROWTYPE;
  v_ship ships%ROWTYPE;
  v_cost integer;
BEGIN
  -- Get player data
  SELECT * INTO v_player FROM players WHERE user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'player_not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship data
  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'ship_not_found', 'message', 'Ship not found'));
  END IF;

  -- Check if player is at a special port
  PERFORM 1 FROM ports p
  JOIN sectors s ON p.sector_id = s.id
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
      UPDATE ships SET 
        hull_lvl = hull_lvl + 1,
        hull = hull_max,
        cargo = CASE 
          WHEN hull_lvl + 1 = 1 THEN 1000
          WHEN hull_lvl + 1 = 2 THEN 3500
          WHEN hull_lvl + 1 = 3 THEN 7224
          WHEN hull_lvl + 1 = 4 THEN 10000
          WHEN hull_lvl + 1 = 5 THEN 13162
          ELSE FLOOR(1000 * POWER(hull_lvl + 1, 1.8))
        END
      WHERE player_id = v_player.id;
  END CASE;

  -- Deduct credits
  UPDATE players SET credits = credits - v_cost WHERE id = v_player.id;

  -- Get updated ship data
  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;
  SELECT * INTO v_player FROM players WHERE id = v_player.id;

  -- Return success with updated data
  RETURN jsonb_build_object(
    'ok', true,
    'credits', v_player.credits,
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
