-- Check why other AI actions are failing

-- Test 1: Check ai_optimize_trading function
DO $$
DECLARE
    ai_player RECORD;
    v_result BOOLEAN;
BEGIN
    -- Get AI_Alpha's data (he's in sector 3)
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
    
    RAISE NOTICE 'Testing ai_optimize_trading for %', ai_player.name;
    RAISE NOTICE 'Credits: %, Ore: %, Organics: %, Goods: %', ai_player.credits, ai_player.ore, ai_player.organics, ai_player.goods;
    
    -- Check if there are ports in sector 3
    RAISE NOTICE 'Ports in sector 3: %', (SELECT COUNT(*) FROM ports WHERE sector_id = ai_player.sector_id);
    
    -- Test the trading function
    BEGIN
        v_result := public.ai_optimize_trading(ai_player);
        RAISE NOTICE 'ai_optimize_trading result: %', v_result;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Error in ai_optimize_trading: %', SQLERRM;
    END;
END $$;

-- Test 2: Check what ports exist in sector 3
SELECT 
    'Ports in Sector 3' as check_name,
    p.kind as port_kind,
    p.price_ore,
    p.stock_ore
FROM ports p
JOIN sectors s ON p.sector_id = s.id
WHERE s.number = 3 AND s.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID;

-- Test 3: Check what sectors have unclaimed planets
SELECT 
    'Sectors with Unclaimed Planets' as check_name,
    sec.number as sector_number,
    COUNT(p.id) as unclaimed_planets
FROM sectors sec
LEFT JOIN planets p ON sec.id = p.sector_id AND p.owner_player_id IS NULL
WHERE sec.universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID
GROUP BY sec.number
HAVING COUNT(p.id) > 0
ORDER BY sec.number;
