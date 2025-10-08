-- Fix AI Function Sector Reference
-- 
-- The run_ai_player_actions function is trying to access s.sector_id from the ships table,
-- but the ships table doesn't have a sector_id column. The sector is stored in players.current_sector.
-- 
-- This migration fixes the function to use the correct column references.

-- Drop and recreate the function with correct column references
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
BEGIN
    -- Get all AI players in this universe
    FOR ai_player IN 
        SELECT p.id, p.handle, s.id as ship_id, s.credits, p.current_sector as sector_id, s.ore, s.organics, s.goods, s.energy, s.colonists,
               s.hull_lvl, s.engine_lvl, s.comp_lvl, s.sensor_lvl, s.fighters, s.torpedoes,
               sec.number as sector_number
        FROM public.players p
        JOIN public.ships s ON p.id = s.player_id
        LEFT JOIN public.sectors sec ON p.current_sector = sec.id
        WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
    LOOP
        -- Simple AI decision making
        
        -- 1. Check for profitable trading in current sector
        SELECT * INTO v_port_data
        FROM public.ports
        WHERE sector_id = ai_player.sector_id;
        
        IF FOUND THEN
            -- Look for profitable trade opportunities
            -- For now, just do simple buy/sell logic
            
            -- If AI has credits and port has stock, buy something
            IF ai_player.credits > 1000 AND v_port_data.ore > 0 THEN
                UPDATE public.ships
                SET credits = credits - v_port_data.price_ore * 10,
                    ore = ore + 10
                WHERE id = ai_player.ship_id;
                actions_taken := actions_taken + 1;
            END IF;
            
            -- If AI has cargo and port wants it, sell something
            IF ai_player.ore > 0 AND v_port_data.kind != 'ore' THEN
                UPDATE public.ships
                SET credits = credits + v_port_data.price_ore * ai_player.ore,
                    ore = 0
                WHERE id = ai_player.ship_id;
                actions_taken := actions_taken + 1;
            END IF;
        END IF;
        
        -- 2. Simple movement logic - move to a random adjacent sector
        -- For now, just increment sector number (simple implementation)
        v_target_sector := ai_player.sector_number + 1;
        
        -- Get the sector ID for the target sector
        SELECT id INTO v_target_sector_id
        FROM public.sectors
        WHERE universe_id = p_universe_id AND number = v_target_sector;
        
        IF FOUND THEN
            -- Move the AI player
            UPDATE public.players
            SET current_sector = v_target_sector_id
            WHERE id = ai_player.id;
            actions_taken := actions_taken + 1;
        END IF;
        
        -- 3. Simple planet claiming logic
        -- Check if there are unclaimed planets in current sector
        SELECT * INTO v_planets_data
        FROM public.planets
        WHERE sector_id = ai_player.sector_id AND owner_player_id IS NULL
        LIMIT 1;
        
        IF FOUND THEN
            -- Claim the planet
            UPDATE public.planets
            SET owner_player_id = ai_player.id
            WHERE id = v_planets_data.id;
            actions_taken := actions_taken + 1;
        END IF;
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

-- Grant permissions
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO anon;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO authenticated;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO service_role;

-- Test the fixed function
SELECT 'Testing fixed run_ai_player_actions...' as status;
SELECT run_ai_player_actions((SELECT id FROM universes LIMIT 1)) as test_result;
