-- Type-aware trading RPC (overrides previous game_trade)
-- How to apply: Run once in Supabase SQL Editor after assigning port kinds

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
  v_ship RECORD;
  v_port RECORD;
  v_inventory RECORD;
  v_unit_price NUMERIC;
  v_total NUMERIC;
  v_result JSON;
  v_cargo_used INTEGER;
  v_cargo_free INTEGER;
BEGIN
  IF p_action NOT IN ('buy','sell') THEN
    RETURN json_build_object('error', json_build_object('code','invalid_action','message','Invalid action'));
  END IF;
  IF p_resource NOT IN ('ore','organics','goods','energy') THEN
    RETURN json_build_object('error', json_build_object('code','invalid_resource','message','Invalid resource'));
  END IF;
  IF p_qty <= 0 THEN
    RETURN json_build_object('error', json_build_object('code','invalid_qty','message','Quantity must be positive'));
  END IF;

  SELECT p.id, p.credits, p.current_sector
  INTO v_player_id, v_player_credits, v_player_current_sector
  FROM players p WHERE p.user_id = p_user_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  SELECT * INTO v_ship FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  SELECT * INTO v_port FROM ports WHERE id = p_port_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Port not found'));
  END IF;
  IF v_port.sector_id != v_player_current_sector THEN
    RETURN json_build_object('error', json_build_object('code','wrong_sector','message','Player not in port sector'));
  END IF;

  IF v_port.kind = 'special' THEN
    RETURN json_build_object('error', json_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.'));
  END IF;

  SELECT * INTO v_inventory FROM inventories WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Inventory not found'));
  END IF;

  -- Compute unit price using base price and dynamic stock-based multiplier
  DECLARE
    base_price NUMERIC;
    stock_level INTEGER;
    price_multiplier NUMERIC;
  BEGIN
    CASE p_resource
      WHEN 'ore' THEN 
        base_price := v_port.price_ore;
        stock_level := v_port.ore;
      WHEN 'organics' THEN 
        base_price := v_port.price_organics;
        stock_level := v_port.organics;
      WHEN 'goods' THEN 
        base_price := v_port.price_goods;
        stock_level := v_port.goods;
      WHEN 'energy' THEN 
        base_price := v_port.price_energy;
        stock_level := v_port.energy;
    END CASE;
    
    -- Apply dynamic pricing based on stock levels
    price_multiplier := calculate_price_multiplier(stock_level);
    v_unit_price := base_price * price_multiplier;
  END;

  IF p_action = 'buy' THEN
    -- For buy: port must SELL the resource if it's its kind; otherwise only BUY other resources (reject)
    IF p_resource = v_port.kind THEN
      v_unit_price := v_unit_price * 0.90; -- sell price (player buys)
      -- Check stock
      IF (p_resource='ore' AND v_port.ore < p_qty) OR
         (p_resource='organics' AND v_port.organics < p_qty) OR
         (p_resource='goods' AND v_port.goods < p_qty) OR
         (p_resource='energy' AND v_port.energy < p_qty) THEN
        RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
      END IF;
    ELSE
      RETURN json_build_object('error', json_build_object('code','resource_not_allowed','message', 'Can only buy the port''s native commodity'));
    END IF;

    v_total := v_unit_price * p_qty;
    IF v_player_credits < v_total THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_credits','message','Insufficient credits'));
    END IF;

    -- Cargo capacity check: qty <= cargo_free
    v_cargo_used := v_inventory.ore + v_inventory.organics + v_inventory.goods + v_inventory.energy;
    v_cargo_free := GREATEST(v_ship.cargo - v_cargo_used, 0);
    IF p_qty > v_cargo_free THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_cargo','message','Insufficient cargo capacity'));
    END IF;

    UPDATE players SET credits = credits - v_total WHERE id = v_player_id;
    UPDATE inventories SET 
      ore = ore + CASE WHEN p_resource='ore' THEN p_qty ELSE 0 END,
      organics = organics + CASE WHEN p_resource='organics' THEN p_qty ELSE 0 END,
      goods = goods + CASE WHEN p_resource='goods' THEN p_qty ELSE 0 END,
      energy = energy + CASE WHEN p_resource='energy' THEN p_qty ELSE 0 END
    WHERE player_id = v_player_id;
    UPDATE ports SET 
      ore = ore - CASE WHEN p_resource='ore' THEN p_qty ELSE 0 END,
      organics = organics - CASE WHEN p_resource='organics' THEN p_qty ELSE 0 END,
      goods = goods - CASE WHEN p_resource='goods' THEN p_qty ELSE 0 END,
      energy = energy - CASE WHEN p_resource='energy' THEN p_qty ELSE 0 END
    WHERE id = p_port_id;

  ELSIF p_action = 'sell' THEN
    -- For sell: port must BUY resource (any resource except its kind)
    IF p_resource = v_port.kind THEN
      RETURN json_build_object('error', json_build_object('code','resource_not_allowed','message', 'Cannot sell the port''s native commodity here'));
    END IF;
    v_unit_price := v_unit_price * 1.10; -- buy price (player sells to port)

    -- Check player inventory
    IF (p_resource='ore' AND v_inventory.ore < p_qty) OR
       (p_resource='organics' AND v_inventory.organics < p_qty) OR
       (p_resource='goods' AND v_inventory.goods < p_qty) OR
       (p_resource='energy' AND v_inventory.energy < p_qty) THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
    END IF;

    v_total := v_unit_price * p_qty;
    UPDATE players SET credits = credits + v_total WHERE id = v_player_id;
    UPDATE inventories SET 
      ore = ore - CASE WHEN p_resource='ore' THEN p_qty ELSE 0 END,
      organics = organics - CASE WHEN p_resource='organics' THEN p_qty ELSE 0 END,
      goods = goods - CASE WHEN p_resource='goods' THEN p_qty ELSE 0 END,
      energy = energy - CASE WHEN p_resource='energy' THEN p_qty ELSE 0 END
    WHERE player_id = v_player_id;
    UPDATE ports SET 
      ore = ore + CASE WHEN p_resource='ore' THEN p_qty ELSE 0 END,
      organics = organics + CASE WHEN p_resource='organics' THEN p_qty ELSE 0 END,
      goods = goods + CASE WHEN p_resource='goods' THEN p_qty ELSE 0 END,
      energy = energy + CASE WHEN p_resource='energy' THEN p_qty ELSE 0 END
    WHERE id = p_port_id;
  END IF;

  -- Log trade at effective unit price for audit
  INSERT INTO trades (player_id, port_id, action, resource, qty, price)
  VALUES (v_player_id, p_port_id, p_action, p_resource, p_qty, v_unit_price);

  -- Return snapshot
  SELECT credits INTO v_player_credits FROM players WHERE id = v_player_id;
  SELECT * INTO v_inventory FROM inventories WHERE player_id = v_player_id;
  SELECT * INTO v_port FROM ports WHERE id = p_port_id;

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


