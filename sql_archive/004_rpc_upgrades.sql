-- BNT Redux Equipment & Repair RPC Functions
-- How to apply: Run this file once in Supabase SQL Editor after 001_init.sql, 002_seed.sql, and 003_rpc.sql

-- Function to handle equipment upgrades (fighters, torpedoes)
CREATE OR REPLACE FUNCTION game_upgrade(
    p_user_id UUID,
    p_item TEXT,
    p_qty INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_player_credits BIGINT;
    v_current_sector UUID;
    v_port_id UUID;
    v_ship_id UUID;
    v_fighters INTEGER;
    v_torpedoes INTEGER;
    v_unit_cost INTEGER;
    v_total_cost INTEGER;
    v_result JSON;
BEGIN
    -- Validate item type
    IF p_item NOT IN ('fighters', 'torpedoes') THEN
        RETURN json_build_object('error', 'Invalid item type');
    END IF;
    
    IF p_qty <= 0 THEN
        RETURN json_build_object('error', 'Quantity must be positive');
    END IF;
    
    -- Get player info (including current sector)
    SELECT p.id, p.credits, p.current_sector
    INTO v_player_id, v_player_credits, v_current_sector
    FROM players p
    WHERE p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Player not found');
    END IF;

    -- Ensure there is a port in the player's current sector
    SELECT id INTO v_port_id
    FROM ports
    WHERE sector_id = v_current_sector;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'No port in current sector');
    END IF;
    
    -- Get ship info
    SELECT s.id, s.fighters, s.torpedoes
    INTO v_ship_id, v_fighters, v_torpedoes
    FROM ships s
    WHERE s.player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Ship not found');
    END IF;
    
    -- Set unit cost based on item
    CASE p_item
        WHEN 'fighters' THEN v_unit_cost := 50;
        WHEN 'torpedoes' THEN v_unit_cost := 120;
    END CASE;
    
    v_total_cost := v_unit_cost * p_qty;
    
    -- Check if player has enough credits
    IF v_player_credits < v_total_cost THEN
        RETURN json_build_object('error', 'Insufficient credits');
    END IF;
    
    -- Perform the upgrade
    IF p_item = 'fighters' THEN
        UPDATE ships SET fighters = fighters + p_qty WHERE id = v_ship_id;
        UPDATE players SET credits = credits - v_total_cost WHERE id = v_player_id;
        
        -- Log the purchase (audit)
        INSERT INTO trades (player_id, port_id, action, resource, qty, price)
        VALUES (v_player_id, v_port_id, 'buy', 'fighters', p_qty, v_unit_cost);
        
        -- Get updated values
        SELECT fighters INTO v_fighters FROM ships WHERE id = v_ship_id;
        SELECT credits INTO v_player_credits FROM players WHERE id = v_player_id;
        
    ELSIF p_item = 'torpedoes' THEN
        UPDATE ships SET torpedoes = torpedoes + p_qty WHERE id = v_ship_id;
        UPDATE players SET credits = credits - v_total_cost WHERE id = v_player_id;
        
        -- Log the purchase (audit)
        INSERT INTO trades (player_id, port_id, action, resource, qty, price)
        VALUES (v_player_id, v_port_id, 'buy', 'torpedoes', p_qty, v_unit_cost);
        
        -- Get updated values
        SELECT torpedoes INTO v_torpedoes FROM ships WHERE id = v_ship_id;
        SELECT credits INTO v_player_credits FROM players WHERE id = v_player_id;
    END IF;
    
    -- Return success
    RETURN json_build_object(
        'ok', true,
        'credits', v_player_credits,
        'ship', json_build_object(
            'fighters', v_fighters,
            'torpedoes', v_torpedoes
        )
    );
END;
$$;

-- Function to handle hull repair
CREATE OR REPLACE FUNCTION game_repair(
    p_user_id UUID,
    p_hull INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_player_credits BIGINT;
    v_current_sector UUID;
    v_port_id UUID;
    v_ship_id UUID;
    v_current_hull INTEGER;
    v_hull_max INTEGER := 100;
    v_hull_repair_cost INTEGER := 2;
    v_actual_repair INTEGER;
    v_total_cost INTEGER;
    v_result JSON;
BEGIN
    IF p_hull <= 0 THEN
        RETURN json_build_object('error', 'Repair amount must be positive');
    END IF;
    
    -- Get player info (including current sector)
    SELECT p.id, p.credits, p.current_sector
    INTO v_player_id, v_player_credits, v_current_sector
    FROM players p
    WHERE p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Player not found');
    END IF;
    
    -- Get ship info
    SELECT s.id, s.hull
    INTO v_ship_id, v_current_hull
    FROM ships s
    WHERE s.player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Ship not found');
    END IF;
    
    -- Calculate actual repair (capped at max hull)
    v_actual_repair := LEAST(p_hull, v_hull_max - v_current_hull);
    
    IF v_actual_repair <= 0 THEN
        RETURN json_build_object('error', 'Hull is already at maximum');
    END IF;
    
    v_total_cost := v_actual_repair * v_hull_repair_cost;
    
    -- Check if player has enough credits
    IF v_player_credits < v_total_cost THEN
        RETURN json_build_object('error', 'Insufficient credits');
    END IF;
    
    -- Perform the repair
    UPDATE ships SET hull = hull + v_actual_repair WHERE id = v_ship_id;
    UPDATE players SET credits = credits - v_total_cost WHERE id = v_player_id;
    
    -- Log the repair as an audit row (resource label 'hull_repair') if a port exists here
    SELECT id INTO v_port_id
    FROM ports
    WHERE sector_id = v_current_sector;

    IF FOUND THEN
        INSERT INTO trades (player_id, port_id, action, resource, qty, price)
        VALUES (v_player_id, v_port_id, 'buy', 'hull_repair', v_actual_repair, v_hull_repair_cost);
    END IF;

    -- Get updated values
    SELECT hull INTO v_current_hull FROM ships WHERE id = v_ship_id;
    SELECT credits INTO v_player_credits FROM players WHERE id = v_player_id;
    
    -- Return success
    RETURN json_build_object(
        'ok', true,
        'credits', v_player_credits,
        'ship', json_build_object(
            'hull', v_current_hull
        )
    );
END;
$$;
