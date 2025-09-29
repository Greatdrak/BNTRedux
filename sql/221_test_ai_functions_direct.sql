-- Test the AI functions directly with proper parameters

-- Test 1: Test ai_make_decision function directly
-- First, let's get the AI player data as individual variables
DO $$
DECLARE
    v_player_id UUID;
    v_player_name TEXT;
    v_personality ai_personality;
    v_ship_id UUID;
    v_credits BIGINT;
    v_sector_id UUID;
    v_ore INTEGER;
    v_organics INTEGER;
    v_goods INTEGER;
    v_energy INTEGER;
    v_colonists INTEGER;
    v_fighters INTEGER;
    v_torpedoes INTEGER;
    v_sector_number INTEGER;
    v_universe_id UUID;
    v_decision TEXT;
    v_memory RECORD;
BEGIN
    -- Get AI_Alpha's data
    SELECT p.id, p.handle, p.ai_personality, s.id, s.credits, p.current_sector, 
           s.ore, s.organics, s.goods, s.energy, s.colonists, s.fighters, s.torpedoes,
           sec.number, sec.universe_id
    INTO v_player_id, v_player_name, v_personality, v_ship_id, v_credits, v_sector_id,
         v_ore, v_organics, v_goods, v_energy, v_colonists, v_fighters, v_torpedoes,
         v_sector_number, v_universe_id
    FROM players p
    JOIN ships s ON p.id = s.player_id
    JOIN sectors sec ON p.current_sector = sec.id
    WHERE p.handle = 'AI_Alpha' AND p.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID;
    
    -- Get AI memory
    SELECT * INTO v_memory FROM ai_player_memory WHERE player_id = v_player_id;
    
    -- Test the decision function
    v_decision := public.ai_make_decision(v_player_id, v_player_name, v_personality, v_ship_id, v_credits, v_sector_id, v_ore, v_organics, v_goods, v_energy, v_colonists, v_fighters, v_torpedoes, v_sector_number, v_universe_id, v_memory);
    
    RAISE NOTICE 'AI Decision for %: %', v_player_name, v_decision;
END $$;
