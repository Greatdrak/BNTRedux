-- Simple test to debug the RECORD issue

-- Test 1: Check what fields are actually in the ai_player RECORD
DO $$
DECLARE
    ai_player RECORD;
    ai_memory RECORD;
    v_decision TEXT;
BEGIN
    -- Get AI_Alpha's data
    SELECT p.id, p.handle as name, p.ai_personality, 
           s.id as ship_id, s.credits, p.current_sector as sector_id, s.ore, s.organics, s.goods, s.energy, s.colonists,
           s.hull_lvl, s.engine_lvl, s.power_lvl, s.comp_lvl, s.sensor_lvl, s.beam_lvl,
           s.armor_lvl, s.cloak_lvl, s.torp_launcher_lvl, s.shield_lvl, s.fighters, s.torpedoes,
           sec.number as sector_number, sec.universe_id
    INTO ai_player
    FROM players p
    JOIN ships s ON p.id = s.player_id
    JOIN sectors sec ON p.current_sector = sec.id
    WHERE p.handle = 'AI_Alpha' AND p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID;
    
    -- Get AI memory
    SELECT * INTO ai_memory FROM ai_player_memory WHERE player_id = ai_player.id;
    
    -- Test the decision function
    BEGIN
        v_decision := public.ai_make_decision(ai_player, ai_memory);
        RAISE NOTICE 'AI Decision for %: %', ai_player.name, v_decision;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Error in ai_make_decision: %', SQLERRM;
    END;
END $$;
