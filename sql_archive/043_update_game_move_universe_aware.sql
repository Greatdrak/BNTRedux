-- Update game_move and game_hyperspace functions to be universe-aware
-- How to apply: Run once in Supabase SQL Editor

-- Function to handle player movement with validation (universe-aware)
CREATE OR REPLACE FUNCTION game_move(
    p_user_id UUID,
    p_to_sector_number INTEGER,
    p_universe_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_current_sector RECORD;
    v_target_sector RECORD;
    v_warp_exists BOOLEAN;
    v_result JSON;
BEGIN
    -- Get player info - filter by universe if provided
    IF p_universe_id IS NOT NULL THEN
        SELECT p.*, s.number as current_sector_number
        INTO v_player
        FROM players p
        JOIN sectors s ON p.current_sector = s.id
        WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
    ELSE
        SELECT p.*, s.number as current_sector_number
        INTO v_player
        FROM players p
        JOIN sectors s ON p.current_sector = s.id
        WHERE p.user_id = p_user_id;
    END IF;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Player not found');
    END IF;
    
    -- Check if player has turns
    IF v_player.turns <= 0 THEN
        RETURN json_build_object('error', 'No turns remaining');
    END IF;
    
    -- Get current sector info
    SELECT * INTO v_current_sector
    FROM sectors
    WHERE id = v_player.current_sector;
    
    -- Get target sector info - filter by universe if provided
    IF p_universe_id IS NOT NULL THEN
        SELECT * INTO v_target_sector
        FROM sectors
        WHERE number = p_to_sector_number AND universe_id = p_universe_id;
    ELSE
        SELECT * INTO v_target_sector
        FROM sectors
        WHERE number = p_to_sector_number;
    END IF;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Target sector not found');
    END IF;
    
    -- Check if warp exists from current to target
    SELECT EXISTS(
        SELECT 1 FROM warps w
        WHERE w.from_sector = v_player.current_sector
        AND w.to_sector = v_target_sector.id
    ) INTO v_warp_exists;
    
    IF NOT v_warp_exists THEN
        RETURN json_build_object('error', 'No warp connection to target sector');
    END IF;
    
    -- Perform the move
    UPDATE players 
    SET current_sector = v_target_sector.id, turns = turns - 1
    WHERE id = v_player.id;
    
    -- Return success with updated player info
    SELECT json_build_object(
        'ok', true,
        'message', 'Move successful',
        'player', json_build_object(
            'id', v_player.id,
            'handle', v_player.handle,
            'turns', v_player.turns - 1,
            'current_sector', v_target_sector.id,
            'current_sector_number', v_target_sector.number
        )
    ) INTO v_result;
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', 'Move operation failed: ' || SQLERRM);
END;
$$;

-- Hyperspace jump by sector number with engine-based turn cost (universe-aware)
CREATE OR REPLACE FUNCTION game_hyperspace(
  p_user_id UUID,
  p_target_sector_number INT,
  p_universe_id UUID DEFAULT NULL
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
  v_cost := GREATEST(1, CEIL(ABS(p_target_sector_number - v_current_number) / GREATEST(1, v_engine_lvl)));

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
