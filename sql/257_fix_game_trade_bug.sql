-- Fix the bug in game_trade function - wrong parameter name
-- The function exists but has a bug: uses p_port instead of p_port_id

CREATE OR REPLACE FUNCTION public.game_trade(
  p_user_id UUID,
  p_port_id UUID,
  p_action TEXT,
  p_resource TEXT,
  p_qty INTEGER,
  p_universe_id UUID DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID;
  v_player_current_sector UUID;
  v_ship RECORD;
  v_port RECORD;
  v_unit_price NUMERIC;
  v_total NUMERIC;
  v_cargo_used INTEGER;
  v_cargo_free INTEGER;
BEGIN
  -- Validate inputs
  IF p_action NOT IN ('buy','sell') THEN
    RETURN json_build_object('error', json_build_object('code','invalid_action','message','Invalid action'));
  END IF;
  IF p_resource NOT IN ('ore','organics','goods','energy') THEN
    RETURN json_build_object('error', json_build_object('code','invalid_resource','message','Invalid resource'));
  END IF;
  IF p_qty <= 0 THEN
    RETURN json_build_object('error', json_build_object('code','invalid_qty','message','Quantity must be positive'));
  END IF;

  -- Get player info - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT p.id, p.current_sector
    INTO v_player_id, v_player_current_sector
    FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
  ELSE
    SELECT p.id, p.current_sector
    INTO v_player_id, v_player_current_sector
    FROM players p WHERE p.user_id = p_user_id;
  END IF;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  -- Get ship data (includes credits and inventory)
  SELECT * INTO v_ship FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  -- Get port data - FIX: use p_port_id not p_port
  SELECT * INTO v_port FROM ports WHERE id = p_port_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Port not found'));
  END IF;

  -- Check if player is in the same sector as the port
  IF v_player_current_sector != v_port.sector_id THEN
    RETURN json_build_object('error', json_build_object('code','wrong_sector','message','You must be in the same sector as the port'));
  END IF;

  -- Calculate unit price based on port type and resource
  CASE p_resource
    WHEN 'ore' THEN
      v_unit_price := v_port.price_ore;
    WHEN 'organics' THEN
      v_unit_price := v_port.price_organics;
    WHEN 'goods' THEN
      v_unit_price := v_port.price_goods;
    WHEN 'energy' THEN
      v_unit_price := v_port.price_energy;
  END CASE;

  v_total := v_unit_price * p_qty;

  -- Handle buy action
  IF p_action = 'buy' THEN
    -- Check if player has enough credits
    IF v_ship.credits < v_total THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_credits','message','Insufficient credits'));
    END IF;

    -- Check cargo capacity
    v_cargo_used := v_ship.ore + v_ship.organics + v_ship.goods;
    v_cargo_free := v_ship.cargo - v_cargo_used;
    IF p_qty > v_cargo_free THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_cargo','message','Insufficient cargo space'));
    END IF;

    -- Check if port has enough stock
    CASE p_resource
      WHEN 'ore' THEN
        IF v_port.ore < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
        END IF;
      WHEN 'organics' THEN
        IF v_port.organics < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
        END IF;
      WHEN 'goods' THEN
        IF v_port.goods < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
        END IF;
      WHEN 'energy' THEN
        IF v_port.energy < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
        END IF;
    END CASE;

    -- Execute buy transaction
    UPDATE ships SET 
      credits = credits - v_total,
      ore = CASE WHEN p_resource = 'ore' THEN ore + p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics + p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods + p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy + p_qty ELSE energy END
    WHERE id = v_ship.id;
    
    UPDATE ports SET 
      ore = CASE WHEN p_resource = 'ore' THEN ore - p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics - p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods - p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy - p_qty ELSE energy END,
      credits = credits + v_total
    WHERE id = p_port_id;

  -- Handle sell action
  ELSE
    -- Check if player has enough inventory
    CASE p_resource
      WHEN 'ore' THEN
        IF v_ship.ore < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
        END IF;
      WHEN 'organics' THEN
        IF v_ship.organics < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
        END IF;
      WHEN 'goods' THEN
        IF v_ship.goods < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
        END IF;
      WHEN 'energy' THEN
        IF v_ship.energy < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
        END IF;
    END CASE;

    -- Execute sell transaction
    UPDATE ships SET 
      credits = credits + v_total,
      ore = CASE WHEN p_resource = 'ore' THEN ore - p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics - p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods - p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy - p_qty ELSE energy END
    WHERE id = v_ship.id;
    
    UPDATE ports SET 
      ore = CASE WHEN p_resource = 'ore' THEN ore + p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics + p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods + p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy + p_qty ELSE energy END,
      credits = credits - v_total
    WHERE id = p_port_id;
  END IF;

  -- Return success result
  RETURN json_build_object(
    'success', true,
    'message', 'Trade completed successfully',
    'action', p_action,
    'resource', p_resource,
    'quantity', p_qty,
    'unit_price', v_unit_price,
    'total', v_total,
    'ship_credits_after', v_ship.credits + CASE WHEN p_action = 'buy' THEN -v_total ELSE v_total END
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Exception in game_trade: %', SQLERRM;
    RETURN json_build_object('error', json_build_object('code','internal_error','message','Internal server error: ' || SQLERRM));
END;
$$;
