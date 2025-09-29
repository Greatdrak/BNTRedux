-- AI Combat and Movement Functions for Enhanced Xenobe Behavior

-- AI Buy Fighters Function
CREATE OR REPLACE FUNCTION public.ai_buy_fighters(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_port RECORD;
    v_fighter_capacity INTEGER;
    v_fighters_to_buy INTEGER;
    v_cost BIGINT;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Check if we're at a special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- Calculate fighter capacity
        v_fighter_capacity := (100 * POWER(1.5, ai_player.comp_lvl - 1))::INTEGER;
        
        -- Determine how many fighters to buy
        v_fighters_to_buy := LEAST(v_fighter_capacity - ai_player.fighters, 50);
        
        IF v_fighters_to_buy > 0 THEN
            v_cost := v_fighters_to_buy * 100; -- Assume 100 credits per fighter
            
            IF ai_player.credits >= v_cost THEN
                UPDATE ships SET 
                    credits = credits - v_cost,
                    fighters = fighters + v_fighters_to_buy
                WHERE id = ai_player.ship_id;
                v_success := TRUE;
            END IF;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Upgrade Weapons Function
CREATE OR REPLACE FUNCTION public.ai_upgrade_weapons(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_port RECORD;
    v_upgrade_type TEXT;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Check if we're at a special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- Prioritize weapon upgrades for warriors
        IF ai_player.beam_lvl < 10 THEN
            SELECT game_ship_upgrade(ai_player.ship_id, 'beam_weapons') INTO v_success;
        ELSIF ai_player.torp_launcher_lvl < 8 THEN
            SELECT game_ship_upgrade(ai_player.ship_id, 'torpedo_launchers') INTO v_success;
        ELSIF ai_player.armor_lvl < 8 THEN
            SELECT game_ship_upgrade(ai_player.ship_id, 'armor') INTO v_success;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Upgrade Engines Function
CREATE OR REPLACE FUNCTION public.ai_upgrade_engines(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_port RECORD;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Check if we're at a special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- Upgrade engines for exploration
        IF ai_player.engine_lvl < 15 THEN
            SELECT game_ship_upgrade(ai_player.ship_id, 'engine') INTO v_success;
        ELSIF ai_player.sensor_lvl < 10 THEN
            SELECT game_ship_upgrade(ai_player.ship_id, 'sensors') INTO v_success;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Patrol Territory Function
CREATE OR REPLACE FUNCTION public.ai_patrol_territory(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_target_sector RECORD;
    v_owned_planets INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find sectors with our planets to patrol
    SELECT s.id, s.number, COUNT(p.id) as planet_count
    INTO v_target_sector
    FROM sectors s
    JOIN planets p ON p.sector_id = s.id
    WHERE p.owner_player_id = ai_player.id
    AND s.id != ai_player.sector_id
    GROUP BY s.id, s.number
    ORDER BY RANDOM()
    LIMIT 1;
    
    IF FOUND THEN
        -- Move to patrol that sector
        UPDATE ships SET sector_id = v_target_sector.id WHERE id = ai_player.ship_id;
        v_success := TRUE;
    ELSE
        -- No owned planets to patrol, do strategic movement
        v_success := public.ai_strategic_move(ai_player);
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Strategic Move Function
CREATE OR REPLACE FUNCTION public.ai_strategic_move(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_target_sector RECORD;
    v_move_score INTEGER;
    v_best_score INTEGER := -1;
    v_best_sector RECORD;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find strategic sectors to move to
    FOR v_target_sector IN
        SELECT s.id, s.number,
               (SELECT COUNT(*) FROM ports p WHERE p.sector_id = s.id) as port_count,
               (SELECT COUNT(*) FROM planets pl WHERE pl.sector_id = s.id AND pl.owner_player_id IS NULL) as free_planets,
               (SELECT COUNT(*) FROM ships sh JOIN players pl ON sh.player_id = pl.id 
                WHERE sh.sector_id = s.id AND pl.is_ai = FALSE) as human_count,
               (SELECT COUNT(*) FROM ships sh JOIN players pl ON sh.player_id = pl.id 
                WHERE sh.sector_id = s.id AND pl.is_ai = TRUE AND pl.id != ai_player.id) as ai_count
        FROM sectors s
        WHERE s.universe_id = ai_player.universe_id
        AND s.id != ai_player.sector_id
        ORDER BY RANDOM()
        LIMIT 15
    LOOP
        -- Calculate movement score based on personality
        v_move_score := 0;
        
        CASE ai_player.ai_personality
            WHEN 'trader' THEN
                v_move_score := v_target_sector.port_count * 5 + v_target_sector.human_count * 3;
                
            WHEN 'explorer' THEN
                v_move_score := v_target_sector.free_planets * 4 + (15 - v_target_sector.ai_count - v_target_sector.human_count) * 2;
                
            WHEN 'warrior' THEN
                v_move_score := v_target_sector.human_count * 6 + v_target_sector.ai_count * 3 + v_target_sector.port_count * 2;
                
            WHEN 'colonizer' THEN
                v_move_score := v_target_sector.free_planets * 8 + v_target_sector.port_count * 2;
                
            ELSE -- balanced
                v_move_score := v_target_sector.port_count * 2 + v_target_sector.free_planets * 3 + v_target_sector.human_count * 1;
        END CASE;
        
        -- Add randomness
        v_move_score := v_move_score + (RANDOM() * 5)::INTEGER;
        
        IF v_move_score > v_best_score THEN
            v_best_score := v_move_score;
            v_best_sector := v_target_sector;
        END IF;
    END LOOP;
    
    -- Move to best sector
    IF v_best_sector.id IS NOT NULL THEN
        UPDATE ships SET sector_id = v_best_sector.id WHERE id = ai_player.ship_id;
        v_success := TRUE;
    END IF;
    
    RETURN v_success;
END;
$$;

-- AI Basic Action Function (fallback for simple actions)
CREATE OR REPLACE FUNCTION public.ai_basic_action(ai_player RECORD, action TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
    v_target_sector RECORD;
BEGIN
    CASE action
        WHEN 'basic_trade' THEN
            -- Simple trading logic
            SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id;
            
            IF FOUND THEN
                IF ai_player.credits > 1000 AND v_port.ore > 0 THEN
                    UPDATE ships SET 
                        credits = credits - v_port.price_ore * 10,
                        ore = ore + 10
                    WHERE id = ai_player.ship_id AND credits >= v_port.price_ore * 10;
                    v_success := TRUE;
                END IF;
            END IF;
            
        WHEN 'explore' THEN
            -- Random exploration
            SELECT id INTO v_target_sector
            FROM sectors
            WHERE universe_id = ai_player.universe_id
            AND id != ai_player.sector_id
            ORDER BY RANDOM()
            LIMIT 1;
            
            IF FOUND THEN
                UPDATE ships SET sector_id = v_target_sector.id WHERE id = ai_player.ship_id;
                v_success := TRUE;
            END IF;
            
        WHEN 'trade_goods' THEN
            v_success := public.ai_optimize_trading(ai_player);
            
        WHEN 'resource_gather' THEN
            v_success := public.ai_emergency_trade(ai_player);
            
        WHEN 'expand_territory' THEN
            v_success := public.ai_strategic_explore(ai_player, NULL);
            
        WHEN 'raid_trade' THEN
            -- Aggressive trading (buy low, sell high quickly)
            v_success := public.ai_optimize_trading(ai_player);
            
        WHEN 'trade_for_funds' THEN
            v_success := public.ai_emergency_trade(ai_player);
            
        WHEN 'explore_markets' THEN
            v_success := public.ai_strategic_move(ai_player);
    END CASE;
    
    RETURN v_success;
END;
$$;

-- Create wrapper function that extends existing AI system
CREATE OR REPLACE FUNCTION public.cron_run_ai_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSON;
    v_settings RECORD;
    v_enhanced_enabled BOOLEAN := FALSE;
BEGIN
    -- Check if enhanced AI is enabled for this universe
    SELECT ai_actions_enabled INTO v_enhanced_enabled 
    FROM universe_settings 
    WHERE universe_id = p_universe_id;
    
    -- Use enhanced AI system if enabled, otherwise fall back to existing system
    IF v_enhanced_enabled = TRUE THEN
        -- Use enhanced AI system (extends existing functionality)
        SELECT public.run_enhanced_ai_actions(p_universe_id) INTO v_result;
    ELSE
        -- Use existing AI system (preserves current behavior)
        SELECT public.run_ai_player_actions(p_universe_id) INTO v_result;
    END IF;
    
    RETURN v_result;
END;
$$;
