-- Emergency Warp System Implementation (Fixed)
-- Skip table/index creation and just add the functions

-- Function to calculate average tech level for a ship (reuse from mine system)
CREATE OR REPLACE FUNCTION public.calculate_ship_avg_tech_level(p_player_id uuid)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_ship RECORD;
    v_avg_tech numeric;
BEGIN
    -- Get ship data
    SELECT 
        hull_lvl,
        engine_lvl,
        comp_lvl,
        sensor_lvl,
        shield_lvl,
        power_lvl,
        beam_lvl,
        torp_launcher_lvl,
        cloak_lvl
    INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    
    -- Calculate average tech level
    v_avg_tech := (
        v_ship.hull_lvl + 
        v_ship.engine_lvl + 
        v_ship.comp_lvl + 
        v_ship.sensor_lvl + 
        v_ship.shield_lvl + 
        v_ship.power_lvl + 
        v_ship.beam_lvl + 
        v_ship.torp_launcher_lvl + 
        v_ship.cloak_lvl
    ) / 9.0;
    
    RETURN v_avg_tech;
END;
$$;

-- Function to perform emergency warp
CREATE OR REPLACE FUNCTION public.emergency_warp(
    p_player_id uuid,
    p_universe_id uuid,
    p_target_sector_number integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_current_sector RECORD;
    v_target_sector RECORD;
    v_avg_tech numeric;
    v_degradation_threshold numeric;
    v_degradation_applied boolean := false;
    v_hull_damage integer := 0;
    v_random_sector RECORD;
    v_result jsonb;
BEGIN
    -- Get player data
    SELECT * INTO v_player
    FROM public.players
    WHERE id = p_player_id AND universe_id = p_universe_id;
    
    -- Get ship data
    SELECT * INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Player or ship not found');
    END IF;
    
    -- Check if ship has emergency warp device
    IF NOT v_ship.device_emergency_warp THEN
        RETURN jsonb_build_object('error', 'Emergency warp device not installed');
    END IF;
    
    -- Get current sector info
    SELECT * INTO v_current_sector
    FROM public.sectors
    WHERE id = v_player.current_sector;
    
    -- Determine target sector
    IF p_target_sector_number IS NOT NULL THEN
        -- Specific target sector
        SELECT * INTO v_target_sector
        FROM public.sectors
        WHERE number = p_target_sector_number AND universe_id = p_universe_id;
        
        IF NOT FOUND THEN
            RETURN jsonb_build_object('error', 'Target sector not found');
        END IF;
    ELSE
        -- Random sector (emergency escape)
        SELECT * INTO v_random_sector
        FROM public.sectors
        WHERE universe_id = p_universe_id
          AND id != v_player.current_sector
        ORDER BY RANDOM()
        LIMIT 1;
        
        IF NOT FOUND THEN
            RETURN jsonb_build_object('error', 'No sectors available for emergency warp');
        END IF;
        
        v_target_sector := v_random_sector;
    END IF;
    
    -- Calculate average tech level
    v_avg_tech := public.calculate_ship_avg_tech_level(p_player_id);
    
    -- Get degradation threshold from universe settings
    SELECT avg_tech_level_emergency_warp_degrades INTO v_degradation_threshold
    FROM public.universe_settings
    WHERE universe_id = p_universe_id;
    
    -- Default threshold if not set
    IF v_degradation_threshold IS NULL THEN
        v_degradation_threshold := 13;
    END IF;
    
    -- Check if degradation should be applied
    IF v_avg_tech >= v_degradation_threshold THEN
        v_degradation_applied := true;
        -- Calculate hull damage based on tech level (higher tech = more damage)
        v_hull_damage := GREATEST(1, FLOOR((v_avg_tech - v_degradation_threshold) * 2));
        
        -- Apply hull damage
        UPDATE public.ships 
        SET hull = GREATEST(0, hull - v_hull_damage)
        WHERE player_id = p_player_id;
    END IF;
    
    -- Move player to target sector
    UPDATE public.players 
    SET current_sector = v_target_sector.id
    WHERE id = p_player_id;
    
    -- Record the emergency warp event (if table exists)
    BEGIN
        INSERT INTO public.emergency_warp_events (
            player_id,
            universe_id,
            from_sector_id,
            to_sector_id,
            avg_tech_level_at_use,
            degradation_applied,
            hull_damage_taken
        ) VALUES (
            p_player_id,
            p_universe_id,
            v_current_sector.id,
            v_target_sector.id,
            v_avg_tech,
            v_degradation_applied,
            v_hull_damage
        );
    EXCEPTION
        WHEN undefined_table THEN
            -- Table doesn't exist, skip logging
            NULL;
    END;
    
    -- Build result
    v_result := jsonb_build_object(
        'success', true,
        'message', 'Emergency warp successful',
        'from_sector', v_current_sector.number,
        'to_sector', v_target_sector.number,
        'avg_tech_level', v_avg_tech,
        'degradation_threshold', v_degradation_threshold,
        'degradation_applied', v_degradation_applied,
        'hull_damage_taken', v_hull_damage,
        'hull_remaining', v_ship.hull - v_hull_damage
    );
    
    RETURN v_result;
END;
$$;

-- Function to get emergency warp device status
CREATE OR REPLACE FUNCTION public.get_emergency_warp_status(p_player_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_ship RECORD;
    v_avg_tech numeric;
    v_degradation_threshold numeric;
    v_universe_id uuid;
BEGIN
    -- Get ship data
    SELECT * INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    -- Get universe_id
    SELECT universe_id INTO v_universe_id
    FROM public.players
    WHERE id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Ship not found');
    END IF;
    
    -- Calculate average tech level
    v_avg_tech := public.calculate_ship_avg_tech_level(p_player_id);
    
    -- Get degradation threshold from universe settings
    SELECT avg_tech_level_emergency_warp_degrades INTO v_degradation_threshold
    FROM public.universe_settings
    WHERE universe_id = v_universe_id;
    
    -- Default threshold if not set
    IF v_degradation_threshold IS NULL THEN
        v_degradation_threshold := 13;
    END IF;
    
    RETURN jsonb_build_object(
        'device_installed', v_ship.device_emergency_warp,
        'avg_tech_level', v_avg_tech,
        'degradation_threshold', v_degradation_threshold,
        'will_degrade', v_avg_tech >= v_degradation_threshold,
        'estimated_damage', CASE 
            WHEN v_avg_tech >= v_degradation_threshold THEN 
                GREATEST(1, FLOOR((v_avg_tech - v_degradation_threshold) * 2))
            ELSE 0
        END
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.calculate_ship_avg_tech_level(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emergency_warp(uuid, uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_emergency_warp_status(uuid) TO authenticated;

-- Set ownership
ALTER FUNCTION public.calculate_ship_avg_tech_level(uuid) OWNER TO postgres;
ALTER FUNCTION public.emergency_warp(uuid, uuid, integer) OWNER TO postgres;
ALTER FUNCTION public.get_emergency_warp_status(uuid) OWNER TO postgres;
