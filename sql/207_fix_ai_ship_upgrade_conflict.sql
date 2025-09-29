-- Fix AI Ship Upgrade Function Conflict
-- The AI functions are calling game_ship_upgrade with ship_id, but the function expects user_id
-- We need to create an AI-specific version or fix the calls

-- Option 1: Create an AI-specific ship upgrade function
CREATE OR REPLACE FUNCTION public.ai_ship_upgrade(
    p_ship_id UUID,
    p_attr TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ship RECORD;
    v_cost INTEGER;
    v_current_level INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Get ship info
    SELECT s.*, p.current_sector INTO v_ship 
    FROM ships s
    JOIN players p ON s.player_id = p.id
    WHERE s.id = p_ship_id;
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Check if ship is at a Special port
    IF NOT EXISTS (
        SELECT 1 FROM ports p 
        JOIN sectors s ON p.sector_id = s.id 
        WHERE s.id = v_ship.current_sector AND p.kind = 'special'
    ) THEN
        RETURN FALSE;
    END IF;

    -- Get current level and calculate cost
    CASE p_attr
        WHEN 'engine' THEN 
            v_current_level := v_ship.engine_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'computer' THEN 
            v_current_level := v_ship.comp_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'sensors' THEN 
            v_current_level := v_ship.sensor_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'beam_weapons' THEN 
            v_current_level := v_ship.beam_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'torpedo_launchers' THEN 
            v_current_level := v_ship.torp_launcher_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'armor' THEN 
            v_current_level := v_ship.armor_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'power' THEN 
            v_current_level := v_ship.power_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        ELSE
            RETURN FALSE;
    END CASE;

    -- Check if ship has enough credits
    IF v_ship.credits < v_cost THEN
        RETURN FALSE;
    END IF;

    -- Apply upgrade and deduct credits
    CASE p_attr
        WHEN 'engine' THEN 
            UPDATE ships SET engine_lvl = engine_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'computer' THEN 
            UPDATE ships SET comp_lvl = comp_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'sensors' THEN 
            UPDATE ships SET sensor_lvl = sensor_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'beam_weapons' THEN 
            UPDATE ships SET beam_lvl = beam_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'torpedo_launchers' THEN 
            UPDATE ships SET torp_launcher_lvl = torp_launcher_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'armor' THEN 
            UPDATE ships SET armor_lvl = armor_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'power' THEN 
            UPDATE ships SET power_lvl = power_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
    END CASE;

    v_success := TRUE;
    RETURN v_success;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.ai_ship_upgrade(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_ship_upgrade(UUID, TEXT) TO service_role;

-- Now update the AI functions to use the correct function name
CREATE OR REPLACE FUNCTION public.ai_upgrade_weapons(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
BEGIN
    -- Check if at Special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- Prioritize weapon upgrades for warriors
        IF ai_player.beam_lvl < 10 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'beam_weapons');
        ELSIF ai_player.torp_launcher_lvl < 8 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'torpedo_launchers');
        ELSIF ai_player.armor_lvl < 8 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'armor');
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

CREATE OR REPLACE FUNCTION public.ai_upgrade_engines(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
BEGIN
    -- Check if at Special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- Upgrade engines for exploration
        IF ai_player.engine_lvl < 15 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'engine');
        ELSIF ai_player.sensor_lvl < 10 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'sensors');
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

CREATE OR REPLACE FUNCTION public.ai_upgrade_ship(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
BEGIN
    -- Check if at Special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- General upgrades based on current levels
        IF ai_player.hull_lvl < 10 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'hull');
        ELSIF ai_player.power_lvl < 8 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'power');
        ELSIF ai_player.comp_lvl < 8 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'computer');
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- Test the fix
SELECT 'AI Ship Upgrade Function Created Successfully' as status;
