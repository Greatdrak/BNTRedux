-- BNT Redux RPC Functions
-- How to apply: Run this file once in Supabase SQL Editor after 001_init.sql and 002_seed.sql

-- Function to handle player movement with validation
CREATE OR REPLACE FUNCTION game_move(
    p_user_id UUID,
    p_to_sector_number INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_current_sector RECORD;
    v_target_sector RECORD;
    v_warp_exists BOOLEAN;
    v_result JSON;
BEGIN
    -- Get player info
    SELECT p.*, s.number as current_sector_number
    INTO v_player
    FROM players p
    JOIN sectors s ON p.current_sector = s.id
    WHERE p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Player not found');
    END IF;
    
    -- Check if player has turns
    IF v_player.turns < 1 THEN
        RETURN json_build_object('error', 'Insufficient turns');
    END IF;
    
    -- Get target sector
    SELECT * INTO v_target_sector
    FROM sectors s
    JOIN universes u ON s.universe_id = u.id
    WHERE u.name = 'Alpha' AND s.number = p_to_sector_number;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Target sector not found');
    END IF;
    
    -- Check if warp exists from current to target
    SELECT EXISTS(
        SELECT 1 FROM warps w
        WHERE w.from_sector = v_player.current_sector
        AND w.to_sector = v_target_sector.id
    ) INTO v_warp_exists;
    
    IF NOT v_warp_exists THEN
        RETURN json_build_object('error', 'No warp connection to target sector');
    END IF;
    
    -- Perform the move
    UPDATE players 
    SET current_sector = v_target_sector.id, turns = turns - 1
    WHERE id = v_player.id;
    
    -- Return success
    RETURN json_build_object(
        'ok', true,
        'player', json_build_object(
            'current_sector', v_target_sector.id,
            'turns', v_player.turns - 1
        )
    );
END;
$$;

-- Function to handle trading with validation
CREATE OR REPLACE FUNCTION game_trade(
    p_user_id UUID,
    p_port_id UUID,
    p_action TEXT,
    p_resource TEXT,
    p_qty INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_player_credits BIGINT;
    v_player_current_sector UUID;
    v_port RECORD;
    v_inventory RECORD;
    v_cost NUMERIC;
    v_total_cost NUMERIC;
    v_result JSON;
BEGIN
    -- Validate action and resource
    IF p_action NOT IN ('buy', 'sell') THEN
        RETURN json_build_object('error', 'Invalid action');
    END IF;
    
    IF p_resource NOT IN ('ore', 'organics', 'goods', 'energy') THEN
        RETURN json_build_object('error', 'Invalid resource');
    END IF;
    
    IF p_qty <= 0 THEN
        RETURN json_build_object('error', 'Quantity must be positive');
    END IF;
    
    -- Get player info
    SELECT p.id, p.credits, p.current_sector
    INTO v_player_id, v_player_credits, v_player_current_sector
    FROM players p
    WHERE p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Player not found');
    END IF;
    
    -- Get port info
    SELECT p.*
    INTO v_port
    FROM ports p
    WHERE p.id = p_port_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Port not found');
    END IF;
    
    -- Check if player is in the same sector as port
    IF v_player_current_sector != v_port.sector_id THEN
        RETURN json_build_object('error', 'Player not in port sector');
    END IF;
    
    -- Get player inventory
    SELECT * INTO v_inventory
    FROM inventories
    WHERE player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Player inventory not found');
    END IF;
    
    -- Calculate cost based on resource and action
    CASE p_resource
        WHEN 'ore' THEN v_cost := v_port.price_ore;
        WHEN 'organics' THEN v_cost := v_port.price_organics;
        WHEN 'goods' THEN v_cost := v_port.price_goods;
        WHEN 'energy' THEN v_cost := v_port.price_energy;
    END CASE;
    
    v_total_cost := v_cost * p_qty;
    
    -- Validate trade based on action
    IF p_action = 'buy' THEN
        -- Check if player has enough credits
        IF v_player_credits < v_total_cost THEN
            RETURN json_build_object('error', 'Insufficient credits');
        END IF;
        
        -- Check if port has enough stock
        CASE p_resource
            WHEN 'ore' THEN
                IF v_port.ore < p_qty THEN
                    RETURN json_build_object('error', 'Insufficient port stock');
                END IF;
            WHEN 'organics' THEN
                IF v_port.organics < p_qty THEN
                    RETURN json_build_object('error', 'Insufficient port stock');
                END IF;
            WHEN 'goods' THEN
                IF v_port.goods < p_qty THEN
                    RETURN json_build_object('error', 'Insufficient port stock');
                END IF;
            WHEN 'energy' THEN
                IF v_port.energy < p_qty THEN
                    RETURN json_build_object('error', 'Insufficient port stock');
                END IF;
        END CASE;
        
        -- Perform buy transaction
        UPDATE players SET credits = credits - v_total_cost WHERE id = v_player_id;
        UPDATE inventories SET 
            ore = ore + CASE WHEN p_resource = 'ore' THEN p_qty ELSE 0 END,
            organics = organics + CASE WHEN p_resource = 'organics' THEN p_qty ELSE 0 END,
            goods = goods + CASE WHEN p_resource = 'goods' THEN p_qty ELSE 0 END,
            energy = energy + CASE WHEN p_resource = 'energy' THEN p_qty ELSE 0 END
        WHERE player_id = v_player_id;
        
        UPDATE ports SET 
            ore = ore - CASE WHEN p_resource = 'ore' THEN p_qty ELSE 0 END,
            organics = organics - CASE WHEN p_resource = 'organics' THEN p_qty ELSE 0 END,
            goods = goods - CASE WHEN p_resource = 'goods' THEN p_qty ELSE 0 END,
            energy = energy - CASE WHEN p_resource = 'energy' THEN p_qty ELSE 0 END
        WHERE id = p_port_id;
        
    ELSIF p_action = 'sell' THEN
        -- Check if player has enough inventory
        CASE p_resource
            WHEN 'ore' THEN
                IF v_inventory.ore < p_qty THEN
                    RETURN json_build_object('error', 'Insufficient inventory');
                END IF;
            WHEN 'organics' THEN
                IF v_inventory.organics < p_qty THEN
                    RETURN json_build_object('error', 'Insufficient inventory');
                END IF;
            WHEN 'goods' THEN
                IF v_inventory.goods < p_qty THEN
                    RETURN json_build_object('error', 'Insufficient inventory');
                END IF;
            WHEN 'energy' THEN
                IF v_inventory.energy < p_qty THEN
                    RETURN json_build_object('error', 'Insufficient inventory');
                END IF;
        END CASE;
        
        -- Perform sell transaction
        UPDATE players SET credits = credits + v_total_cost WHERE id = v_player_id;
        UPDATE inventories SET 
            ore = ore - CASE WHEN p_resource = 'ore' THEN p_qty ELSE 0 END,
            organics = organics - CASE WHEN p_resource = 'organics' THEN p_qty ELSE 0 END,
            goods = goods - CASE WHEN p_resource = 'goods' THEN p_qty ELSE 0 END,
            energy = energy - CASE WHEN p_resource = 'energy' THEN p_qty ELSE 0 END
        WHERE player_id = v_player_id;
        
        UPDATE ports SET 
            ore = ore + CASE WHEN p_resource = 'ore' THEN p_qty ELSE 0 END,
            organics = organics + CASE WHEN p_resource = 'organics' THEN p_qty ELSE 0 END,
            goods = goods + CASE WHEN p_resource = 'goods' THEN p_qty ELSE 0 END,
            energy = energy + CASE WHEN p_resource = 'energy' THEN p_qty ELSE 0 END
        WHERE id = p_port_id;
    END IF;
    
    -- Log the trade
    INSERT INTO trades (player_id, port_id, action, resource, qty, price)
    VALUES (v_player_id, p_port_id, p_action, p_resource, p_qty, v_cost);
    
    -- Get updated data
    SELECT credits INTO v_player_credits FROM players WHERE id = v_player_id;
    SELECT * INTO v_inventory FROM inventories WHERE player_id = v_player_id;
    SELECT * INTO v_port FROM ports WHERE id = p_port_id;
    
    -- Return success
    RETURN json_build_object(
        'ok', true,
        'player', json_build_object(
            'credits', v_player_credits,
            'inventory', json_build_object(
                'ore', v_inventory.ore,
                'organics', v_inventory.organics,
                'goods', v_inventory.goods,
                'energy', v_inventory.energy
            )
        ),
        'port', json_build_object(
            'stock', json_build_object(
                'ore', v_port.ore,
                'organics', v_port.organics,
                'goods', v_port.goods,
                'energy', v_port.energy
            ),
            'prices', json_build_object(
                'ore', v_port.price_ore,
                'organics', v_port.price_organics,
                'goods', v_port.price_goods,
                'energy', v_port.price_energy
            )
        )
    );
END;
$$;
