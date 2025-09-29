-- Test individual AI action functions to see why they're failing

-- Test 1: Test ai_claim_planet function directly
DO $$
DECLARE
    ai_player RECORD;
    ai_memory RECORD;
    v_result BOOLEAN;
BEGIN
    -- Get AI_Alpha's data (he's in sector 3 with an unclaimed planet)
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
    
    RAISE NOTICE 'Testing ai_claim_planet for %', ai_player.name;
    RAISE NOTICE 'Credits: %, Sector: %', ai_player.credits, ai_player.sector_number;
    
    -- Test the claim planet function
    BEGIN
        v_result := public.ai_claim_planet(ai_player);
        RAISE NOTICE 'ai_claim_planet result: %', v_result;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Error in ai_claim_planet: %', SQLERRM;
    END;
END $$;

-- Test 2: Check if there are unclaimed planets in sector 3
SELECT 
    'Planets in Sector 3' as check_name,
    p.name as planet_name,
    p.owner_player_id,
    CASE WHEN p.owner_player_id IS NULL THEN 'UNCLAIMED' ELSE 'CLAIMED' END as status
FROM planets p
JOIN sectors s ON p.sector_id = s.id
WHERE s.number = 3 AND s.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID;
