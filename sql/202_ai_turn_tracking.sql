-- Add Turn Tracking to AI Actions
-- This allows AI players to show activity level in leaderboard without turn limits

-- Update the enhanced AI action execution to track turns
CREATE OR REPLACE FUNCTION public.ai_execute_action(ai_player RECORD, ai_memory RECORD, action TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
    v_planet RECORD;
    v_target_sector RECORD;
    v_profit BIGINT;
    v_cost BIGINT;
BEGIN
    CASE action
        WHEN 'optimize_trade' THEN
            v_success := public.ai_optimize_trading(ai_player);
            
        WHEN 'emergency_trade' THEN
            v_success := public.ai_emergency_trade(ai_player);
            
        WHEN 'strategic_explore' THEN
            v_success := public.ai_strategic_explore(ai_player, ai_memory);
            
        WHEN 'claim_planet' THEN
            v_success := public.ai_claim_planet(ai_player);
            
        WHEN 'upgrade_ship' THEN
            v_success := public.ai_upgrade_ship(ai_player);
            
        WHEN 'upgrade_weapons' THEN
            v_success := public.ai_upgrade_weapons(ai_player);
            
        WHEN 'upgrade_engines' THEN
            v_success := public.ai_upgrade_engines(ai_player);
            
        WHEN 'buy_fighters' THEN
            v_success := public.ai_buy_fighters(ai_player);
            
        WHEN 'manage_planets' THEN
            v_success := public.ai_manage_planets(ai_player);
            
        WHEN 'patrol_territory' THEN
            v_success := public.ai_patrol_territory(ai_player);
            
        ELSE
            -- Default basic actions
            v_success := public.ai_basic_action(ai_player, action);
    END CASE;
    
    -- Track turn spent for successful actions (for leaderboard activity tracking)
    -- AI players have unlimited turns, but we track their activity level
    IF v_success THEN
        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_action_' || action);
    END IF;
    
    RETURN v_success;
END;
$$;

-- Update AI basic action to also track turns
CREATE OR REPLACE FUNCTION public.ai_basic_action(ai_player RECORD, action TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_target_sector_id UUID;
    v_success BOOLEAN := FALSE;
BEGIN
    IF action = 'move_random' THEN
        SELECT id INTO v_target_sector_id
        FROM public.sectors
        WHERE universe_id = ai_player.universe_id AND id != ai_player.sector_id
        ORDER BY RANDOM()
        LIMIT 1;
        
        IF FOUND THEN
            UPDATE public.ships
            SET sector_id = v_target_sector_id
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- Update AI trading function to track individual trade actions
CREATE OR REPLACE FUNCTION public.ai_optimize_trading(ai_player RECORD)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_port RECORD;
    v_best_profit BIGINT := 0;
    v_best_trade_action TEXT := NULL;
    v_best_commodity TEXT := NULL;
    v_quantity INTEGER := 0;
    v_cargo_space INTEGER;
    v_current_cargo INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Get current ship cargo and capacity
    SELECT 
        COALESCE(ore, 0) + COALESCE(organics, 0) + COALESCE(goods, 0) + COALESCE(energy, 0) + COALESCE(colonists, 0)
    INTO v_current_cargo
    FROM ships WHERE id = ai_player.ship_id;

    SELECT hull_max INTO v_cargo_space FROM ships WHERE id = ai_player.ship_id;

    -- Find ports in the current sector
    FOR v_port IN SELECT * FROM ports WHERE sector_id = ai_player.sector_id
    LOOP
        -- Evaluate selling opportunities
        IF ai_player.ore > 0 AND v_port.kind != 'ore' AND v_port.buy_ore THEN
            IF v_port.price_ore * ai_player.ore > v_best_profit THEN
                v_best_profit := v_port.price_ore * ai_player.ore;
                v_best_trade_action := 'sell';
                v_best_commodity := 'ore';
                v_quantity := ai_player.ore;
            END IF;
        END IF;
        
        -- Similar logic for organics
        IF ai_player.organics > 0 AND v_port.kind != 'organics' AND v_port.buy_organics THEN
            IF v_port.price_organics * ai_player.organics > v_best_profit THEN
                v_best_profit := v_port.price_organics * ai_player.organics;
                v_best_trade_action := 'sell';
                v_best_commodity := 'organics';
                v_quantity := ai_player.organics;
            END IF;
        END IF;
        
        -- Similar logic for goods
        IF ai_player.goods > 0 AND v_port.kind != 'goods' AND v_port.buy_goods THEN
            IF v_port.price_goods * ai_player.goods > v_best_profit THEN
                v_best_profit := v_port.price_goods * ai_player.goods;
                v_best_trade_action := 'sell';
                v_best_commodity := 'goods';
                v_quantity := ai_player.goods;
            END IF;
        END IF;

        -- Evaluate buying opportunities if we have cargo space and credits
        IF v_cargo_space - v_current_cargo > 0 AND ai_player.credits > 1000 THEN
            -- Buy ore if profitable
            IF v_port.kind = 'ore' AND v_port.sell_ore AND v_port.stock_ore > 0 THEN
                IF ai_player.credits >= v_port.price_ore * 10 AND v_port.stock_ore >= 10 THEN
                    IF v_best_profit = 0 THEN -- If no selling opportunity, consider buying
                        v_best_profit := 1;
                        v_best_trade_action := 'buy';
                        v_best_commodity := 'ore';
                        v_quantity := LEAST(10, v_cargo_space - v_current_cargo, v_port.stock_ore);
                    END IF;
                END IF;
            END IF;
            
            -- Similar logic for other commodities...
        END IF;
    END LOOP;

    -- Execute the best trade action
    IF v_best_trade_action = 'sell' THEN
        CASE v_best_commodity
            WHEN 'ore' THEN
                UPDATE ships SET credits = credits + (v_port.price_ore * v_quantity), ore = ore - v_quantity WHERE id = ai_player.ship_id;
            WHEN 'organics' THEN
                UPDATE ships SET credits = credits + (v_port.price_organics * v_quantity), organics = organics - v_quantity WHERE id = ai_player.ship_id;
            WHEN 'goods' THEN
                UPDATE ships SET credits = credits + (v_port.price_goods * v_quantity), goods = goods - v_quantity WHERE id = ai_player.ship_id;
        END CASE;
        v_success := TRUE;
        
    ELSIF v_best_trade_action = 'buy' THEN
        CASE v_best_commodity
            WHEN 'ore' THEN
                UPDATE ships SET credits = credits - (v_port.price_ore * v_quantity), ore = ore + v_quantity WHERE id = ai_player.ship_id;
        END CASE;
        v_success := TRUE;
    END IF;

    RETURN v_success;
END;
$$;

-- Note: AI players now track turns for activity level display in leaderboard
-- They are NOT limited by turns - they can act unlimited times
-- The turn tracking is purely for showing their activity level to other players
