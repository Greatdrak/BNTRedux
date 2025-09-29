-- Test the run_enhanced_ai_actions function with debug output

CREATE OR REPLACE FUNCTION public.test_enhanced_ai_debug(p_universe_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    ai_player RECORD;
    ai_memory RECORD;
    actions_taken INTEGER := 0;
    v_decision TEXT;
    v_action_result BOOLEAN;
    v_debug_output TEXT := '';
BEGIN
    v_debug_output := v_debug_output || 'Starting enhanced AI debug for universe: ' || p_universe_id || E'\n';
    
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
        v_debug_output := v_debug_output || 'Processing AI player: ' || ai_player.name || E'\n';
        
        -- Get or create AI memory
        SELECT * INTO ai_memory FROM ai_player_memory WHERE player_id = ai_player.id;
        
        IF NOT FOUND THEN
            v_debug_output := v_debug_output || 'Creating new memory for: ' || ai_player.name || E'\n';
            INSERT INTO ai_player_memory (player_id, current_goal)
            VALUES (ai_player.id, 'explore')
            RETURNING * INTO ai_memory;
        ELSE
            v_debug_output := v_debug_output || 'Found existing memory for: ' || ai_player.name || E'\n';
        END IF;
        
        -- Make decisions based on personality
        v_decision := public.ai_make_decision(ai_player, ai_memory);
        v_debug_output := v_debug_output || 'Decision for ' || ai_player.name || ': ' || v_decision || E'\n';
        
        -- Execute the decision
        v_action_result := public.ai_execute_action(ai_player, ai_memory, v_decision);
        v_debug_output := v_debug_output || 'Action result for ' || ai_player.name || ': ' || v_action_result || E'\n';
        
        IF v_action_result THEN
            actions_taken := actions_taken + 1;
            v_debug_output := v_debug_output || 'Action successful for ' || ai_player.name || E'\n';
        ELSE
            v_debug_output := v_debug_output || 'Action failed for ' || ai_player.name || E'\n';
        END IF;
        
        -- Update AI memory
        UPDATE ai_player_memory 
        SET last_action = NOW(), 
            updated_at = NOW()
        WHERE player_id = ai_player.id;
        
        v_debug_output := v_debug_output || 'Updated memory for ' || ai_player.name || E'\n';
    END LOOP;
    
    v_debug_output := v_debug_output || 'Total actions taken: ' || actions_taken || E'\n';
    RETURN v_debug_output;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN v_debug_output || 'ERROR: ' || SQLERRM;
END;
$$;

-- Test the debug function
SELECT public.test_enhanced_ai_debug('34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID) as debug_output;
