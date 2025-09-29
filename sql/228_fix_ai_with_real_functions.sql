-- Fix AI system to use existing player functions instead of custom ones

-- Step 1: Create simplified AI decision function focused on core gameplay
CREATE OR REPLACE FUNCTION public.ai_make_simple_decision(ai_player RECORD, ai_memory RECORD)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_ports_in_sector INTEGER;
    v_unclaimed_planets INTEGER;
    v_has_cargo BOOLEAN;
    v_can_afford_upgrade BOOLEAN;
    v_random NUMERIC := RANDOM();
BEGIN
    -- Check current sector status
    SELECT COUNT(*) INTO v_ports_in_sector FROM ports WHERE sector_id = ai_player.sector_id;
    SELECT COUNT(*) INTO v_unclaimed_planets FROM planets p WHERE p.sector_id = ai_player.sector_id AND p.owner_player_id IS NULL;
    
    -- Check player status
    v_has_cargo := (ai_player.ore > 0 OR ai_player.organics > 0 OR ai_player.goods > 0);
    v_can_afford_upgrade := (ai_player.credits >= 1000 * POWER(2, ai_player.hull_lvl));
    
    -- Simple decision tree based on current situation
    IF v_unclaimed_planets > 0 AND ai_player.credits >= 10000 THEN
        RETURN 'claim_planet';
    ELSIF v_ports_in_sector > 0 AND v_has_cargo THEN
        RETURN 'trade_at_port';
    ELSIF v_can_afford_upgrade THEN
        RETURN 'upgrade_ship';
    ELSE
        RETURN 'explore_sectors';
    END IF;
END;
$$;

-- Step 2: Create AI action function focused on core gameplay
CREATE OR REPLACE FUNCTION public.ai_execute_real_action(ai_player RECORD, ai_memory RECORD, action TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_target_sector_id UUID;
    v_planet_id UUID;
    v_result JSONB;
    v_ports_in_sector INTEGER;
    v_unclaimed_planets INTEGER;
    v_credits_needed BIGINT;
BEGIN
    -- Check current sector status
    SELECT COUNT(*) INTO v_ports_in_sector FROM ports WHERE sector_id = ai_player.sector_id;
    SELECT COUNT(*) INTO v_unclaimed_planets FROM planets p WHERE p.sector_id = ai_player.sector_id AND p.owner_player_id IS NULL;
    
    CASE action
        WHEN 'claim_planet' THEN
            -- Only try to claim if there are unclaimed planets
            IF v_unclaimed_planets > 0 THEN
                SELECT id INTO v_planet_id
                FROM planets p
                WHERE p.sector_id = ai_player.sector_id AND p.owner_player_id IS NULL
                LIMIT 1;
                
                IF FOUND THEN
                    SELECT public.game_planet_claim(ai_player.id, v_planet_id) INTO v_result;
                    v_success := (v_result->>'success')::BOOLEAN;
                END IF;
            END IF;
            
        WHEN 'trade_at_port' THEN
            -- Only try to trade if there are ports in the sector
            IF v_ports_in_sector > 0 THEN
                -- Try to sell cargo if we have any
                IF ai_player.ore > 0 OR ai_player.organics > 0 OR ai_player.goods > 0 THEN
                    -- Use existing trade function (simplified - just sell ore for now)
                    IF ai_player.ore > 0 THEN
                        SELECT public.game_trade(ai_player.id, 'ore', ai_player.ore, 'sell') INTO v_result;
                        v_success := (v_result->>'success')::BOOLEAN;
                    END IF;
                END IF;
            END IF;
            
        WHEN 'upgrade_ship' THEN
            -- Try to upgrade the cheapest available upgrade
            IF ai_player.hull_lvl < 10 THEN
                v_credits_needed := 1000 * POWER(2, ai_player.hull_lvl);
                IF ai_player.credits >= v_credits_needed THEN
                    SELECT public.game_ship_upgrade(ai_player.id, ai_player.ship_id, 'hull') INTO v_result;
                    v_success := (v_result->>'success')::BOOLEAN;
                END IF;
            ELSIF ai_player.engine_lvl < 10 THEN
                v_credits_needed := 1000 * POWER(2, ai_player.engine_lvl);
                IF ai_player.credits >= v_credits_needed THEN
                    SELECT public.game_ship_upgrade(ai_player.id, ai_player.ship_id, 'engine') INTO v_result;
                    v_success := (v_result->>'success')::BOOLEAN;
                END IF;
            END IF;
            
        WHEN 'explore_sectors' THEN
            -- Move to a random sector to explore
            SELECT s.id INTO v_target_sector_id
            FROM sectors s
            WHERE s.universe_id = ai_player.universe_id 
            AND s.id != ai_player.sector_id
            ORDER BY RANDOM()
            LIMIT 1;
            
            IF FOUND THEN
                SELECT public.game_move(ai_player.id, v_target_sector_id) INTO v_result;
                v_success := (v_result->>'success')::BOOLEAN;
            END IF;
            
        ELSE
            -- Default: explore (move to random sector)
            SELECT s.id INTO v_target_sector_id
            FROM sectors s
            WHERE s.universe_id = ai_player.universe_id 
            AND s.id != ai_player.sector_id
            ORDER BY RANDOM()
            LIMIT 1;
            
            IF FOUND THEN
                SELECT public.game_move(ai_player.id, v_target_sector_id) INTO v_result;
                v_success := (v_result->>'success')::BOOLEAN;
            END IF;
    END CASE;
    
    RETURN v_success;
END;
$$;

-- Step 2: Update the enhanced AI system to use the real action function
CREATE OR REPLACE FUNCTION public.run_enhanced_ai_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    ai_player RECORD;
    ai_memory RECORD;
    actions_taken INTEGER := 0;
    v_result JSON;
    v_decision TEXT;
    v_action_result BOOLEAN;
BEGIN
    -- Process each AI player
    FOR ai_player IN 
        SELECT p.id, p.handle as name, p.ai_personality, 
               s.id as ship_id, s.credits, p.current_sector as sector_id, s.ore, s.organics, s.goods, s.energy, s.colonists,
               s.hull_lvl, s.engine_lvl, s.power_lvl, s.comp_lvl, s.sensor_lvl, s.beam_lvl,
               s.armor_lvl, s.cloak_lvl, s.torp_launcher_lvl, s.shield_lvl, s.fighters, s.torpedoes,
               sec.number as sector_number, sec.universe_id
        FROM public.players p
        JOIN public.ships s ON p.id = s.player_id
        JOIN public.sectors sec ON p.current_sector = sec.id
        WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
    LOOP
        -- Get or create AI memory
        SELECT * INTO ai_memory FROM ai_player_memory WHERE player_id = ai_player.id;
        
        IF NOT FOUND THEN
            INSERT INTO ai_player_memory (player_id, current_goal)
            VALUES (ai_player.id, 'explore')
            RETURNING * INTO ai_memory;
        END IF;
        
        -- Make decisions based on current situation (simplified logic)
        v_decision := public.ai_make_simple_decision(ai_player, ai_memory);
        
        -- Execute the decision using REAL player functions
        v_action_result := public.ai_execute_real_action(ai_player, ai_memory, v_decision);
        
        IF v_action_result THEN
            actions_taken := actions_taken + 1;
        END IF;
        
        -- Update AI memory
        UPDATE ai_player_memory 
        SET last_action = NOW(), 
            updated_at = NOW()
        WHERE player_id = ai_player.id;
    END LOOP;
    
    v_result := json_build_object(
        'success', TRUE,
        'message', 'Enhanced AI actions completed',
        'actions_taken', actions_taken,
        'universe_id', p_universe_id
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', 'Failed to run enhanced AI actions: ' || SQLERRM);
END;
$$;
