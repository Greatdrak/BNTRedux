-- Realspace Movement Engine Level Scaling
-- At engine level 15+, realspace travel costs 1 turn for any distance
-- Below level 15, the turn cost scales based on distance and engine level

CREATE OR REPLACE FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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
  -- Load player, current sector, ship - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT p.id, p.turns, p.current_sector
    INTO v_player_id, v_turns, v_current_sector_id
    FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
  ELSE
    SELECT p.id, p.turns, p.current_sector
    INTO v_player_id, v_turns, v_current_sector_id
    FROM players p WHERE p.user_id = p_user_id;
  END IF;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  SELECT s.number INTO v_current_number FROM sectors s WHERE s.id = v_current_sector_id;

  -- Get target sector - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT id INTO v_target_sector_id 
    FROM sectors 
    WHERE number = p_target_sector_number AND universe_id = p_universe_id;
  ELSE
    SELECT id INTO v_target_sector_id 
    FROM sectors 
    WHERE number = p_target_sector_number;
  END IF;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Target sector not found'));
  END IF;

  -- Get engine level
  SELECT engine_lvl INTO v_engine_lvl FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  -- Calculate cost
  -- At engine level 15+, cost is 1 turn for any distance; scales based on distance at lower levels
  IF v_engine_lvl >= 15 THEN
    v_cost := 1;
  ELSE
    v_cost := GREATEST(1, CEIL(ABS(p_target_sector_number - v_current_number) / GREATEST(1, v_engine_lvl)));
  END IF;

  -- Check turns
  IF v_turns < v_cost THEN
    RETURN json_build_object('error', json_build_object('code','insufficient_turns','message','Not enough turns'));
  END IF;

  -- Perform jump
  UPDATE players SET 
    current_sector = v_target_sector_id,
    turns = turns - v_cost
  WHERE id = v_player_id;

  -- Return success
  RETURN json_build_object(
    'ok', true,
    'message', 'Hyperspace jump successful',
    'cost', v_cost,
    'player', json_build_object(
      'id', v_player_id,
      'turns', v_turns - v_cost,
      'current_sector', v_target_sector_id,
      'current_sector_number', p_target_sector_number
    )
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', json_build_object('code','server_error','message','Hyperspace operation failed: ' || SQLERRM));
END;
$$;
