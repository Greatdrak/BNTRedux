-- Add Turn Tracking to AI Actions
-- 
-- AI players have unlimited turns but their actions should be tracked
-- in the turns_spent column for leaderboard visibility.
-- 
-- The players table already has a turns_spent column and there's a
-- track_turn_spent function that can be used.

-- 1. Update the AI function to track turns for each action
DROP FUNCTION IF EXISTS public.run_ai_player_actions(UUID);

CREATE OR REPLACE FUNCTION public.run_ai_player_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    ai_player RECORD;
    ai_ship RECORD;
    actions_taken INTEGER := 0;
    v_result JSON;
    v_sector_id UUID;
    v_port_data RECORD;
    v_planets_data RECORD;
    v_profit INTEGER;
    v_target_sector INTEGER;
    v_target_sector_id UUID;
    v_personality TEXT;
    v_decision INTEGER;
BEGIN
    -- Get all AI players in this universe with their personality
    FOR ai_player IN 
        SELECT p.id, p.handle, p.ai_personality, s.id as ship_id, s.credits, p.current_sector as sector_id, 
               s.ore, s.organics, s.goods, s.energy, s.colonists, s.fighters, s.torpedoes,
               s.hull_lvl, s.engine_lvl, s.comp_lvl, s.sensor_lvl,
               sec.number as sector_number
        FROM public.players p
        JOIN public.ships s ON p.id = s.player_id
        LEFT JOIN public.sectors sec ON p.current_sector = sec.id
        WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
    LOOP
        v_personality := COALESCE(ai_player.ai_personality, 'balanced');
        v_decision := floor(random() * 100); -- Random decision 0-99
        
        -- Personality-based behavior with turn tracking
        CASE v_personality
            WHEN 'trader' THEN
                -- Trader: 70% trading, 20% movement, 10% other
                IF v_decision < 70 THEN
                    -- Trading behavior
                    SELECT * INTO v_port_data
                    FROM public.ports
                    WHERE sector_id = ai_player.sector_id;
                    
                    IF FOUND THEN
                        -- Aggressive trading - buy low, sell high
                        IF ai_player.credits > 2000 AND v_port_data.ore > 0 AND v_port_data.price_ore < 12 THEN
                            UPDATE public.ships
                            SET credits = credits - v_port_data.price_ore * 20,
                                ore = ore + 20
                            WHERE id = ai_player.ship_id;
                            -- Track turn spent on trading
                            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_trade');
                            actions_taken := actions_taken + 1;
                        END IF;
                        
                        IF ai_player.ore > 0 AND v_port_data.kind != 'ore' AND v_port_data.price_ore > 15 THEN
                            UPDATE public.ships
                            SET credits = credits + v_port_data.price_ore * ai_player.ore,
                                ore = 0
                            WHERE id = ai_player.ship_id;
                            -- Track turn spent on trading
                            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_trade');
                            actions_taken := actions_taken + 1;
                        END IF;
                    END IF;
                ELSIF v_decision < 90 THEN
                    -- Movement to find new trading opportunities
                    v_target_sector := ai_player.sector_number + (floor(random() * 3) - 1);
                    SELECT id INTO v_target_sector_id
                    FROM public.sectors
                    WHERE universe_id = p_universe_id AND number = v_target_sector;
                    
                    IF FOUND THEN
                        UPDATE public.players
                        SET current_sector = v_target_sector_id
                        WHERE id = ai_player.id;
                        -- Track turn spent on movement
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_move');
                        actions_taken := actions_taken + 1;
                    END IF;
                END IF;
                
            WHEN 'explorer' THEN
                -- Explorer: 60% movement, 30% planet claiming, 10% other
                IF v_decision < 60 THEN
                    -- Movement to new sectors
                    v_target_sector := ai_player.sector_number + (floor(random() * 5) - 2);
                    SELECT id INTO v_target_sector_id
                    FROM public.sectors
                    WHERE universe_id = p_universe_id AND number = v_target_sector;
                    
                    IF FOUND THEN
                        UPDATE public.players
                        SET current_sector = v_target_sector_id
                        WHERE id = ai_player.id;
                        -- Track turn spent on movement
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_explore');
                        actions_taken := actions_taken + 1;
                    END IF;
                ELSIF v_decision < 90 THEN
                    -- Planet claiming
                    SELECT * INTO v_planets_data
                    FROM public.planets
                    WHERE sector_id = ai_player.sector_id AND owner_player_id IS NULL
                    LIMIT 1;
                    
                    IF FOUND THEN
                        UPDATE public.planets
                        SET owner_player_id = ai_player.id
                        WHERE id = v_planets_data.id;
                        -- Track turn spent on planet claiming
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_claim_planet');
                        actions_taken := actions_taken + 1;
                    END IF;
                END IF;
                
            WHEN 'warrior' THEN
                -- Warrior: 50% combat prep, 30% movement, 20% other
                IF v_decision < 50 THEN
                    -- Buy fighters and torpedoes
                    SELECT * INTO v_port_data
                    FROM public.ports
                    WHERE sector_id = ai_player.sector_id AND kind = 'special';
                    
                    IF FOUND AND ai_player.credits > 1000 THEN
                        UPDATE public.ships
                        SET credits = credits - 500,
                            fighters = fighters + 5
                        WHERE id = ai_player.ship_id;
                        -- Track turn spent on combat prep
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_combat_prep');
                        actions_taken := actions_taken + 1;
                    END IF;
                ELSIF v_decision < 80 THEN
                    -- Movement to find enemies
                    v_target_sector := ai_player.sector_number + (floor(random() * 3) - 1);
                    SELECT id INTO v_target_sector_id
                    FROM public.sectors
                    WHERE universe_id = p_universe_id AND number = v_target_sector;
                    
                    IF FOUND THEN
                        UPDATE public.players
                        SET current_sector = v_target_sector_id
                        WHERE id = ai_player.id;
                        -- Track turn spent on movement
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_patrol');
                        actions_taken := actions_taken + 1;
                    END IF;
                END IF;
                
            WHEN 'colonizer' THEN
                -- Colonizer: 60% planet management, 25% movement, 15% other
                IF v_decision < 60 THEN
                    -- Planet claiming and management
                    SELECT * INTO v_planets_data
                    FROM public.planets
                    WHERE sector_id = ai_player.sector_id AND owner_player_id IS NULL
                    LIMIT 1;
                    
                    IF FOUND THEN
                        UPDATE public.planets
                        SET owner_player_id = ai_player.id
                        WHERE id = v_planets_data.id;
                        -- Track turn spent on planet claiming
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_colonize');
                        actions_taken := actions_taken + 1;
                    END IF;
                ELSIF v_decision < 85 THEN
                    -- Movement to find new planets
                    v_target_sector := ai_player.sector_number + (floor(random() * 2) - 1);
                    SELECT id INTO v_target_sector_id
                    FROM public.sectors
                    WHERE universe_id = p_universe_id AND number = v_target_sector;
                    
                    IF FOUND THEN
                        UPDATE public.players
                        SET current_sector = v_target_sector_id
                        WHERE id = ai_player.id;
                        -- Track turn spent on movement
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_colonize');
                        actions_taken := actions_taken + 1;
                    END IF;
                END IF;
                
            ELSE -- balanced
                -- Balanced: Mix of all behaviors
                IF v_decision < 30 THEN
                    -- Trading
                    SELECT * INTO v_port_data
                    FROM public.ports
                    WHERE sector_id = ai_player.sector_id;
                    
                    IF FOUND AND ai_player.credits > 1000 AND v_port_data.ore > 0 THEN
                        UPDATE public.ships
                        SET credits = credits - v_port_data.price_ore * 10,
                            ore = ore + 10
                        WHERE id = ai_player.ship_id;
                        -- Track turn spent on trading
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_trade');
                        actions_taken := actions_taken + 1;
                    END IF;
                ELSIF v_decision < 60 THEN
                    -- Movement
                    v_target_sector := ai_player.sector_number + 1;
                    SELECT id INTO v_target_sector_id
                    FROM public.sectors
                    WHERE universe_id = p_universe_id AND number = v_target_sector;
                    
                    IF FOUND THEN
                        UPDATE public.players
                        SET current_sector = v_target_sector_id
                        WHERE id = ai_player.id;
                        -- Track turn spent on movement
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_move');
                        actions_taken := actions_taken + 1;
                    END IF;
                ELSE
                    -- Planet claiming
                    SELECT * INTO v_planets_data
                    FROM public.planets
                    WHERE sector_id = ai_player.sector_id AND owner_player_id IS NULL
                    LIMIT 1;
                    
                    IF FOUND THEN
                        UPDATE public.planets
                        SET owner_player_id = ai_player.id
                        WHERE id = v_planets_data.id;
                        -- Track turn spent on planet claiming
                        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_claim_planet');
                        actions_taken := actions_taken + 1;
                    END IF;
                END IF;
        END CASE;
    END LOOP;
    
    -- Return success with action count
    RETURN json_build_object(
        'success', true,
        'actions_taken', actions_taken,
        'universe_id', p_universe_id,
        'timestamp', now()
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', 'Failed to run AI player actions: ' || SQLERRM);
END;
$$;

-- 2. Grant permissions
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO anon;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO authenticated;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO service_role;

-- 3. Test the enhanced AI function with turn tracking
SELECT 'Testing AI turn tracking...' as status;
SELECT run_ai_player_actions((SELECT id FROM universes LIMIT 1)) as test_result;
