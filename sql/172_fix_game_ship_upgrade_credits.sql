-- Fix game_ship_upgrade function to use ship credits instead of player credits
-- This fixes the "record v_player has no field credits" error

DROP FUNCTION IF EXISTS public.game_ship_upgrade(uuid, text, uuid);

CREATE OR REPLACE FUNCTION public.game_ship_upgrade(
    p_user_id UUID,
    p_attr TEXT,
    p_universe_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_cost INTEGER;
    v_ship_credits BIGINT;
BEGIN
    -- Get player info
    IF p_universe_id IS NOT NULL THEN
        SELECT * INTO v_player FROM players WHERE user_id = p_user_id AND universe_id = p_universe_id;
    ELSE
        SELECT * INTO v_player FROM players WHERE user_id = p_user_id;
    END IF;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
    END IF;

    -- Get ship info
    SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'ship_not_found', 'message', 'Ship not found'));
    END IF;

    -- Check if player is at a Special port
    IF NOT EXISTS (
        SELECT 1 FROM ports p 
        JOIN sectors s ON p.sector_id = s.id 
        WHERE s.id = v_player.current_sector AND p.kind = 'special'
    ) THEN
        RETURN json_build_object('error', json_build_object('code', 'wrong_port', 'message', 'Must be at a Special port to upgrade'));
    END IF;

    -- Calculate cost based on attribute and current level
    CASE p_attr
        WHEN 'engine' THEN v_cost := 500 * (v_ship.engine_lvl + 1);
        WHEN 'computer' THEN v_cost := 1000 * (v_ship.comp_lvl + 1);
        WHEN 'sensors' THEN v_cost := 800 * (v_ship.sensor_lvl + 1);
        WHEN 'shields' THEN v_cost := 1500 * (v_ship.shield_lvl + 1);
        WHEN 'hull' THEN v_cost := 2000 * (v_ship.hull_lvl + 1);
        ELSE
            RETURN json_build_object('error', json_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
    END CASE;

    -- Check if ship has enough credits (use ship credits, not player credits)
    IF v_ship.credits < v_cost THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
    END IF;

    -- Apply upgrade and deduct credits from ship
    CASE p_attr
        WHEN 'engine' THEN 
            UPDATE ships SET engine_lvl = engine_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'computer' THEN 
            UPDATE ships SET comp_lvl = comp_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'sensors' THEN 
            UPDATE ships SET sensor_lvl = sensor_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'shields' THEN 
            UPDATE ships SET shield_lvl = shield_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'hull' THEN 
            UPDATE ships SET hull_lvl = hull_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
    END CASE;

    -- Get updated ship data
    SELECT * INTO v_ship FROM ships WHERE id = v_ship.id;
    SELECT credits INTO v_ship_credits FROM ships WHERE id = v_ship.id;

    -- Return success with updated data
    RETURN json_build_object(
        'success', true,
        'credits', v_ship_credits,
        'cost', v_cost,
        'attribute', p_attr,
        'new_level', CASE p_attr
            WHEN 'engine' THEN v_ship.engine_lvl
            WHEN 'computer' THEN v_ship.comp_lvl
            WHEN 'sensors' THEN v_ship.sensor_lvl
            WHEN 'shields' THEN v_ship.shield_lvl
            WHEN 'hull' THEN v_ship.hull_lvl
        END
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.game_ship_upgrade(uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_ship_upgrade(uuid, text, uuid) TO service_role;
