-- Fix game_ship_upgrade function to use ship credits instead of player credits
-- This aligns with the migration of credits from players table to ships table

CREATE OR REPLACE FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_cost INTEGER;
  v_next_level INTEGER;
BEGIN
  -- Validate attribute (current set; future attrs can be added without changing costs)
  IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
  END IF;

  -- Get player (optionally universe scoped)
  IF p_universe_id IS NOT NULL THEN
    SELECT p.* INTO v_player FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id FOR UPDATE;
  ELSE
    SELECT p.* INTO v_player FROM players p WHERE p.user_id = p_user_id FOR UPDATE;
  END IF;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship
  SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  -- Must be at Special port
  IF NOT EXISTS (
    SELECT 1 FROM ports p JOIN sectors s ON p.sector_id = s.id
    WHERE s.id = v_player.current_sector AND p.kind = 'special'
  ) THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'wrong_port', 'message', 'Must be at a Special port to upgrade'));
  END IF;

  -- Calculate cost based on attribute (matching the original BNT formulas)
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

  -- Check if ship has enough credits (FIXED: was checking player credits)
  IF v_ship.credits < v_cost THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
  END IF;

  -- Perform upgrade and deduct credits from ship (FIXED: was deducting from player)
  CASE p_attr
    WHEN 'engine' THEN 
      UPDATE ships SET engine_lvl = engine_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'computer' THEN 
      UPDATE ships SET comp_lvl = comp_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'sensors' THEN 
      UPDATE ships SET sensor_lvl = sensor_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'shields' THEN 
      UPDATE ships SET shield_lvl = shield_lvl + 1, shield = shield_max, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'hull' THEN 
      UPDATE ships SET 
        hull_lvl = hull_lvl + 1, 
        hull = hull_max, 
        credits = credits - v_cost,
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

  -- Get updated ship data for response
  SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = v_player.id;

  RETURN jsonb_build_object(
    'ok', true, 
    'attribute', p_attr, 
    'next_level', CASE p_attr
      WHEN 'engine' THEN v_ship.engine_lvl
      WHEN 'computer' THEN v_ship.comp_lvl
      WHEN 'sensors' THEN v_ship.sensor_lvl
      WHEN 'shields' THEN v_ship.shield_lvl
      WHEN 'hull' THEN v_ship.hull_lvl
    END, 
    'cost', v_cost, 
    'credits_after', v_ship.credits
  );
END;
$$;
