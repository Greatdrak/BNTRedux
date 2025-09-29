-- Comprehensive Enhanced AI System Fix
-- This migration ensures the enhanced AI system works correctly

-- Step 1: Fix the run_enhanced_ai_actions function with correct schema
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
        
        -- Make decisions based on personality
        v_decision := public.ai_make_decision(ai_player, ai_memory);
        
        -- Execute the decision
        v_action_result := public.ai_execute_action(ai_player, ai_memory, v_decision);
        
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

-- Step 2: Create simplified cron function that always uses enhanced AI
CREATE OR REPLACE FUNCTION public.cron_run_ai_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Always use enhanced AI system (no more toggle needed)
    SELECT public.run_enhanced_ai_actions(p_universe_id) INTO v_result;
    RETURN v_result;
END;
$$;

-- Step 3: Ensure AI personalities are set for existing AI players
UPDATE players 
SET ai_personality = (
    CASE (RANDOM() * 5)::INTEGER
        WHEN 0 THEN 'trader'::ai_personality
        WHEN 1 THEN 'explorer'::ai_personality  
        WHEN 2 THEN 'warrior'::ai_personality
        WHEN 3 THEN 'colonizer'::ai_personality
        ELSE 'balanced'::ai_personality
    END
)
WHERE is_ai = TRUE AND ai_personality IS NULL;

-- Step 4: Create AI memories for existing AI players
INSERT INTO ai_player_memory (player_id, current_goal)
SELECT id, 'explore'
FROM players 
WHERE is_ai = TRUE 
AND id NOT IN (SELECT player_id FROM ai_player_memory);

-- Step 5: Verify the setup
SELECT 
    'Enhanced AI System Status' as status,
    COUNT(*) as total_ai_players,
    COUNT(CASE WHEN ai_personality IS NOT NULL THEN 1 END) as players_with_personalities,
    COUNT(CASE WHEN id IN (SELECT player_id FROM ai_player_memory) THEN 1 END) as players_with_memory
FROM players 
WHERE is_ai = TRUE;

-- Step 6: Test the enhanced AI function
SELECT public.run_enhanced_ai_actions(
    (SELECT id FROM universes LIMIT 1)
) as test_result;
