-- Migration: 332_add_energy_capacity_check_to_trade.sql
-- Purpose: Add energy capacity check to game_trade function before buying energy

CREATE OR REPLACE FUNCTION public.game_trade(
  p_user_id uuid,
  p_port_id uuid,
  p_action text,
  p_resource text,
  p_qty integer,
  p_universe_id uuid
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
  v_player_id uuid;
  v_ship_id uuid;
  v_ship_record record;
  v_port record;
  v_unit_price numeric;
  v_total numeric;
  v_cargo_space integer;
  v_energy_space integer;
BEGIN
  -- Get player and ship
  SELECT p.id, s.id INTO v_player_id, v_ship_id
  FROM players p
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;

  IF v_player_id IS NULL THEN
    RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship details
  SELECT * INTO v_ship_record FROM ships WHERE id = v_ship_id;

  -- Get port details
  SELECT * INTO v_port FROM ports WHERE id = p_port_id;

  IF v_port IS NULL THEN
    RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Port not found'));
  END IF;

  -- Validate action
  IF p_action NOT IN ('buy', 'sell') THEN
    RETURN json_build_object('error', json_build_object('code', 'invalid_action', 'message', 'Action must be buy or sell'));
  END IF;

  -- Get unit price based on resource
  v_unit_price := CASE p_resource
    WHEN 'ore' THEN v_port.price_ore
    WHEN 'organics' THEN v_port.price_organics
    WHEN 'goods' THEN v_port.price_goods
    WHEN 'energy' THEN v_port.price_energy
    ELSE 0
  END;

  v_total := v_unit_price * p_qty;

  -- Handle BUY action
  IF p_action = 'buy' THEN
    -- Check credits
    IF v_ship_record.credits < v_total THEN
      RETURN json_build_object('error', json_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
    END IF;

    -- Check port stock
    CASE p_resource
      WHEN 'ore' THEN 
        IF p_qty > v_port.ore THEN
          RETURN json_build_object('error', json_build_object('code', 'insufficient_stock', 'message', 'Port does not have enough ' || p_resource));
        END IF;
      WHEN 'organics' THEN 
        IF p_qty > v_port.organics THEN
          RETURN json_build_object('error', json_build_object('code', 'insufficient_stock', 'message', 'Port does not have enough ' || p_resource));
        END IF;
      WHEN 'goods' THEN 
        IF p_qty > v_port.goods THEN
          RETURN json_build_object('error', json_build_object('code', 'insufficient_stock', 'message', 'Port does not have enough ' || p_resource));
        END IF;
      WHEN 'energy' THEN 
        IF p_qty > v_port.energy THEN
          RETURN json_build_object('error', json_build_object('code', 'insufficient_stock', 'message', 'Port does not have enough ' || p_resource));
        END IF;
    END CASE;

    -- CRITICAL: Check energy capacity separately (energy doesn't use cargo space)
    IF p_resource = 'energy' THEN
      v_energy_space := v_ship_record.energy_max - v_ship_record.energy;
      IF p_qty > v_energy_space THEN
        RETURN json_build_object('error', json_build_object(
          'code', 'insufficient_energy_capacity', 
          'message', 'Not enough energy capacity (current: ' || v_ship_record.energy || 
                     ', max: ' || v_ship_record.energy_max || 
                     ', available: ' || v_energy_space || 
                     '). Upgrade Power at a Special Port to increase capacity.'
        ));
      END IF;
    ELSE
      -- For non-energy resources, check cargo space
      v_cargo_space := v_ship_record.cargo - (
        COALESCE(v_ship_record.ore, 0) + 
        COALESCE(v_ship_record.organics, 0) + 
        COALESCE(v_ship_record.goods, 0) + 
        COALESCE(v_ship_record.colonists, 0)
      );
      
      IF v_cargo_space < p_qty THEN
        RETURN json_build_object('error', json_build_object(
          'code', 'insufficient_cargo', 
          'message', 'Not enough cargo space (available: ' || v_cargo_space || ')'
        ));
      END IF;
    END IF;

    -- Execute buy transaction
    UPDATE ships 
    SET 
      credits = credits - v_total,
      ore = CASE WHEN p_resource = 'ore' THEN ore + p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics + p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods + p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy + p_qty ELSE energy END,
      colonists = CASE WHEN p_resource = 'colonists' THEN colonists + p_qty ELSE colonists END
    WHERE id = v_ship_id;
    
    -- Update port stock
    CASE p_resource
      WHEN 'ore' THEN UPDATE ports SET ore = ore - p_qty WHERE id = p_port_id;
      WHEN 'organics' THEN UPDATE ports SET organics = organics - p_qty WHERE id = p_port_id;
      WHEN 'goods' THEN UPDATE ports SET goods = goods - p_qty WHERE id = p_port_id;
      WHEN 'energy' THEN UPDATE ports SET energy = energy - p_qty WHERE id = p_port_id;
    END CASE;

    -- Deduct turn
    UPDATE players SET turns = turns - 1 WHERE id = v_player_id;
    
    RETURN json_build_object('success', true, 'action', 'buy', 'resource', p_resource, 'qty', p_qty, 'cost', v_total);

  -- Handle SELL action
  ELSE
    -- Check if ship has enough resource to sell
    CASE p_resource
      WHEN 'ore' THEN 
        IF v_ship_record.ore < p_qty THEN
          RETURN json_build_object('error', json_build_object('code', 'insufficient_resource', 'message', 'Not enough ' || p_resource || ' to sell'));
        END IF;
      WHEN 'organics' THEN 
        IF v_ship_record.organics < p_qty THEN
          RETURN json_build_object('error', json_build_object('code', 'insufficient_resource', 'message', 'Not enough ' || p_resource || ' to sell'));
        END IF;
      WHEN 'goods' THEN 
        IF v_ship_record.goods < p_qty THEN
          RETURN json_build_object('error', json_build_object('code', 'insufficient_resource', 'message', 'Not enough ' || p_resource || ' to sell'));
        END IF;
      WHEN 'energy' THEN 
        IF v_ship_record.energy < p_qty THEN
          RETURN json_build_object('error', json_build_object('code', 'insufficient_resource', 'message', 'Not enough ' || p_resource || ' to sell'));
        END IF;
    END CASE;

    -- Execute sell transaction
    UPDATE ships 
    SET 
      credits = credits + v_total,
      ore = CASE WHEN p_resource = 'ore' THEN ore - p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics - p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods - p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy - p_qty ELSE energy END,
      colonists = CASE WHEN p_resource = 'colonists' THEN colonists - p_qty ELSE colonists END
    WHERE id = v_ship_id;
    
    -- Update port stock (ports buy everything)
    CASE p_resource
      WHEN 'ore' THEN UPDATE ports SET ore = ore + p_qty WHERE id = p_port_id;
      WHEN 'organics' THEN UPDATE ports SET organics = organics + p_qty WHERE id = p_port_id;
      WHEN 'goods' THEN UPDATE ports SET goods = goods + p_qty WHERE id = p_port_id;
      WHEN 'energy' THEN UPDATE ports SET energy = energy + p_qty WHERE id = p_port_id;
    END CASE;

    -- Deduct turn
    UPDATE players SET turns = turns - 1 WHERE id = v_player_id;
    
    RETURN json_build_object('success', true, 'action', 'sell', 'resource', p_resource, 'qty', p_qty, 'profit', v_total);
  END IF;

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('error', json_build_object('code', 'internal_error', 'message', 'Internal server error: ' || SQLERRM));
END;
$$;

