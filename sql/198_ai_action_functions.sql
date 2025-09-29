-- AI Action Functions for Enhanced Xenobe Behavior
-- These functions implement specific AI behaviors for different personality types

-- AI Optimize Trading Function
CREATE OR REPLACE FUNCTION public.ai_optimize_trading(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_port RECORD;
    v_best_deal RECORD;
    v_max_profit BIGINT := 0;
    v_current_profit BIGINT;
    v_can_afford INTEGER;
    v_cargo_space INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Calculate available cargo space
    v_cargo_space := (100 * POWER(1.5, ai_player.hull_lvl - 1))::INTEGER - 
                     (ai_player.ore + ai_player.organics + ai_player.goods + ai_player.colonists);
    
    -- Find the best trading opportunity in current sector
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id;
    
    IF FOUND THEN
        -- Check each commodity for profit potential
        
        -- Ore trading
        IF v_port.ore > 0 AND ai_player.credits >= v_port.price_ore * 10 THEN
            v_can_afford := LEAST(ai_player.credits / v_port.price_ore, v_cargo_space, v_port.ore, 50);
            v_current_profit := v_port.price_ore * v_can_afford * 0.2; -- Estimate 20% profit
            
            IF v_current_profit > v_max_profit THEN
                v_max_profit := v_current_profit;
                v_best_deal := ROW('ore', v_can_afford, v_port.price_ore);
            END IF;
        END IF;
        
        -- Organics trading
        IF v_port.organics > 0 AND ai_player.credits >= v_port.price_organics * 10 THEN
            v_can_afford := LEAST(ai_player.credits / v_port.price_organics, v_cargo_space, v_port.organics, 50);
            v_current_profit := v_port.price_organics * v_can_afford * 0.25; -- Estimate 25% profit
            
            IF v_current_profit > v_max_profit THEN
                v_max_profit := v_current_profit;
                v_best_deal := ROW('organics', v_can_afford, v_port.price_organics);
            END IF;
        END IF;
        
        -- Goods trading
        IF v_port.goods > 0 AND ai_player.credits >= v_port.price_goods * 10 THEN
            v_can_afford := LEAST(ai_player.credits / v_port.price_goods, v_cargo_space, v_port.goods, 50);
            v_current_profit := v_port.price_goods * v_can_afford * 0.3; -- Estimate 30% profit
            
            IF v_current_profit > v_max_profit THEN
                v_max_profit := v_current_profit;
                v_best_deal := ROW('goods', v_can_afford, v_port.price_goods);
            END IF;
        END IF;
        
        -- Execute the best deal
        IF v_max_profit > 1000 THEN -- Only trade if profit is significant
            CASE (v_best_deal).f1
                WHEN 'ore' THEN
                    UPDATE ships SET 
                        credits = credits - ((v_best_deal).f3 * (v_best_deal).f2),
                        ore = ore + (v_best_deal).f2
                    WHERE id = ai_player.ship_id;
                    v_success := TRUE;
                    
                WHEN 'organics' THEN
                    UPDATE ships SET 
                        credits = credits - ((v_best_deal).f3 * (v_best_deal).f2),
                        organics = organics + (v_best_deal).f2
                    WHERE id = ai_player.ship_id;
                    v_success := TRUE;
                    
                WHEN 'goods' THEN
                    UPDATE ships SET 
                        credits = credits - ((v_best_deal).f3 * (v_best_deal).f2),
                        goods = goods + (v_best_deal).f2
                    WHERE id = ai_player.ship_id;
                    v_success := TRUE;
            END CASE;
        END IF;
        
        -- Try to sell existing cargo if we have some
        IF ai_player.ore > 0 AND v_port.kind != 'ore' THEN
            UPDATE ships SET 
                credits = credits + (v_port.price_ore * ai_player.ore * 1.2)::BIGINT,
                ore = 0
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        IF ai_player.organics > 0 AND v_port.kind != 'organics' THEN
            UPDATE ships SET 
                credits = credits + (v_port.price_organics * ai_player.organics * 1.2)::BIGINT,
                organics = 0
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        IF ai_player.goods > 0 AND v_port.kind != 'goods' THEN
            UPDATE ships SET 
                credits = credits + (v_port.price_goods * ai_player.goods * 1.2)::BIGINT,
                goods = 0
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Strategic Exploration Function
CREATE OR REPLACE FUNCTION public.ai_strategic_explore(ai_player RECORD, ai_memory RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_target_sector RECORD;
    v_best_sector RECORD;
    v_best_score INTEGER := -1;
    v_current_score INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find strategic sectors to explore (those with ports, planets, or other players)
    FOR v_target_sector IN
        SELECT s.id, s.number, s.universe_id,
               (SELECT COUNT(*) FROM ports p WHERE p.sector_id = s.id) as port_count,
               (SELECT COUNT(*) FROM planets pl WHERE pl.sector_id = s.id AND pl.owner_player_id IS NULL) as unclaimed_planets,
               (SELECT COUNT(*) FROM ships sh JOIN players p ON sh.player_id = p.id 
                WHERE sh.sector_id = s.id AND p.is_ai = FALSE) as human_players
        FROM sectors s
        WHERE s.universe_id = ai_player.universe_id 
        AND s.id != ai_player.sector_id
        ORDER BY RANDOM()
        LIMIT 10
    LOOP
        -- Calculate exploration score
        v_current_score := v_target_sector.port_count * 3 + 
                          v_target_sector.unclaimed_planets * 5 + 
                          v_target_sector.human_players * 2;
        
        -- Bonus for sectors we haven't visited recently
        IF ai_memory.exploration_targets IS NULL OR 
           NOT (ai_memory.exploration_targets ? v_target_sector.id::TEXT) THEN
            v_current_score := v_current_score + 10;
        END IF;
        
        IF v_current_score > v_best_score THEN
            v_best_score := v_current_score;
            v_best_sector := v_target_sector;
        END IF;
    END LOOP;
    
    -- Move to the best sector
    IF v_best_sector.id IS NOT NULL THEN
        UPDATE ships SET sector_id = v_best_sector.id WHERE id = ai_player.ship_id;
        
        -- Update exploration memory
        UPDATE ai_player_memory 
        SET exploration_targets = COALESCE(exploration_targets, '[]'::jsonb) || 
                                 jsonb_build_object(v_best_sector.id::TEXT, NOW()::TEXT),
            target_sector_id = v_best_sector.id
        WHERE player_id = ai_player.id;
        
        v_success := TRUE;
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Claim Planet Function
CREATE OR REPLACE FUNCTION public.ai_claim_planet(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_planet RECORD;
    v_claim_cost BIGINT := 10000;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find unclaimed planet in current sector
    SELECT * INTO v_planet
    FROM planets
    WHERE sector_id = ai_player.sector_id 
    AND owner_player_id IS NULL
    ORDER BY RANDOM()
    LIMIT 1;
    
    IF FOUND AND ai_player.credits >= v_claim_cost THEN
        -- Claim the planet
        UPDATE planets
        SET owner_player_id = ai_player.id,
            colonists = 1000 + (RANDOM() * 500)::INTEGER,
            ore = 1000 + (RANDOM() * 2000)::INTEGER,
            organics = 1000 + (RANDOM() * 2000)::INTEGER,
            goods = 500 + (RANDOM() * 1000)::INTEGER,
            energy = 1500 + (RANDOM() * 1000)::INTEGER
        WHERE id = v_planet.id;
        
        -- Deduct cost
        UPDATE ships
        SET credits = credits - v_claim_cost
        WHERE id = ai_player.ship_id;
        
        -- Update AI memory
        UPDATE ai_player_memory 
        SET owned_planets = owned_planets + 1,
            current_goal = 'manage_planets'
        WHERE player_id = ai_player.id;
        
        v_success := TRUE;
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Ship Upgrade Function
CREATE OR REPLACE FUNCTION public.ai_upgrade_ship(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_upgrade_type TEXT;
    v_upgrade_cost BIGINT;
    v_current_level INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Determine what to upgrade based on personality and current levels
    CASE ai_player.ai_personality
        WHEN 'trader' THEN
            -- Traders prioritize hull and engines
            IF ai_player.hull_lvl < 8 THEN
                v_upgrade_type := 'hull';
                v_current_level := ai_player.hull_lvl;
            ELSIF ai_player.engine_lvl < 6 THEN
                v_upgrade_type := 'engine';
                v_current_level := ai_player.engine_lvl;
            END IF;
            
        WHEN 'explorer' THEN
            -- Explorers prioritize engines and sensors
            IF ai_player.engine_lvl < 10 THEN
                v_upgrade_type := 'engine';
                v_current_level := ai_player.engine_lvl;
            ELSIF ai_player.sensor_lvl < 6 THEN
                v_upgrade_type := 'sensors';
                v_current_level := ai_player.sensor_lvl;
            END IF;
            
        WHEN 'warrior' THEN
            -- Warriors prioritize weapons and armor
            IF ai_player.beam_lvl < 8 THEN
                v_upgrade_type := 'beam_weapons';
                v_current_level := ai_player.beam_lvl;
            ELSIF ai_player.armor_lvl < 8 THEN
                v_upgrade_type := 'armor';
                v_current_level := ai_player.armor_lvl;
            END IF;
            
        WHEN 'colonizer' THEN
            -- Colonizers prioritize hull and power
            IF ai_player.hull_lvl < 10 THEN
                v_upgrade_type := 'hull';
                v_current_level := ai_player.hull_lvl;
            ELSIF ai_player.power_lvl < 6 THEN
                v_upgrade_type := 'power';
                v_current_level := ai_player.power_lvl;
            END IF;
            
        ELSE -- balanced
            -- Balanced upgrades
            IF ai_player.hull_lvl < 6 THEN
                v_upgrade_type := 'hull';
                v_current_level := ai_player.hull_lvl;
            ELSIF ai_player.engine_lvl < 5 THEN
                v_upgrade_type := 'engine';
                v_current_level := ai_player.engine_lvl;
            ELSIF ai_player.power_lvl < 5 THEN
                v_upgrade_type := 'power';
                v_current_level := ai_player.power_lvl;
            END IF;
    END CASE;
    
    -- Calculate upgrade cost using BNT formula
    IF v_upgrade_type IS NOT NULL THEN
        v_upgrade_cost := 1000 * POWER(2, v_current_level);
        
        IF ai_player.credits >= v_upgrade_cost THEN
            -- Perform the upgrade using the existing game function
            SELECT game_ship_upgrade(ai_player.ship_id, v_upgrade_type) INTO v_success;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Emergency Trade Function (when low on credits)
CREATE OR REPLACE FUNCTION public.ai_emergency_trade(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_port RECORD;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find any port in current sector
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id;
    
    IF FOUND THEN
        -- Sell any cargo we have for quick credits
        IF ai_player.ore > 0 THEN
            UPDATE ships SET 
                credits = credits + (v_port.price_ore * ai_player.ore)::BIGINT,
                ore = 0
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        IF ai_player.organics > 0 THEN
            UPDATE ships SET 
                credits = credits + (v_port.price_organics * ai_player.organics)::BIGINT,
                organics = 0
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        IF ai_player.goods > 0 THEN
            UPDATE ships SET 
                credits = credits + (v_port.price_goods * ai_player.goods)::BIGINT,
                goods = 0
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        -- If still low on credits, buy cheapest available commodity
        IF NOT v_success AND ai_player.credits >= 100 THEN
            IF v_port.ore > 0 AND v_port.price_ore <= ai_player.credits THEN
                UPDATE ships SET 
                    credits = credits - v_port.price_ore * 5,
                    ore = ore + 5
                WHERE id = ai_player.ship_id AND credits >= v_port.price_ore * 5;
                v_success := TRUE;
            END IF;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Planet Management Function
CREATE OR REPLACE FUNCTION public.ai_manage_planets(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_planet RECORD;
    v_success BOOLEAN := FALSE;
    v_transfer_amount INTEGER;
BEGIN
    -- Find our planets and optimize their production
    FOR v_planet IN
        SELECT * FROM planets 
        WHERE owner_player_id = ai_player.id
        ORDER BY RANDOM()
        LIMIT 3
    LOOP
        -- Transfer resources between ship and planet strategically
        
        -- If planet needs colonists and we have some
        IF v_planet.colonists < 5000 AND ai_player.colonists > 100 THEN
            v_transfer_amount := LEAST(ai_player.colonists, 1000);
            
            UPDATE planets SET colonists = colonists + v_transfer_amount WHERE id = v_planet.id;
            UPDATE ships SET colonists = colonists - v_transfer_amount WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        -- If we need cargo space and planet has excess resources
        IF ai_player.ore + ai_player.organics + ai_player.goods < 500 THEN
            IF v_planet.ore > 3000 THEN
                v_transfer_amount := 1000;
                UPDATE planets SET ore = ore - v_transfer_amount WHERE id = v_planet.id;
                UPDATE ships SET ore = ore + v_transfer_amount WHERE id = ai_player.ship_id;
                v_success := TRUE;
            ELSIF v_planet.organics > 3000 THEN
                v_transfer_amount := 1000;
                UPDATE planets SET organics = organics - v_transfer_amount WHERE id = v_planet.id;
                UPDATE ships SET organics = organics + v_transfer_amount WHERE id = ai_player.ship_id;
                v_success := TRUE;
            END IF;
        END IF;
        
        -- Store excess ship cargo on planets
        IF ai_player.ore > 1000 THEN
            UPDATE planets SET ore = ore + ai_player.ore WHERE id = v_planet.id;
            UPDATE ships SET ore = 0 WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
    END LOOP;
    
    RETURN v_success;
END;
$$;
