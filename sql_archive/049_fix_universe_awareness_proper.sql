-- Fix Universe Awareness Issues - Proper Implementation
-- This script updates existing RPC functions to be universe-aware without breaking functionality

-- 1. Fix game_trade RPC function - Add universe_id parameter
CREATE OR REPLACE FUNCTION game_trade(
  p_user_id UUID,
  p_port_id UUID,
  p_action TEXT,
  p_resource TEXT,
  p_qty INTEGER,
  p_universe_id UUID DEFAULT NULL
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

  -- Get player info - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT p.id, p.credits, p.current_sector
    INTO v_player_id, v_player_credits, v_player_current_sector
    FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
  ELSE
    SELECT p.id, p.credits, p.current_sector
    INTO v_player_id, v_player_credits, v_player_current_sector
    FROM players p WHERE p.user_id = p_user_id;
  END IF;
  
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

  -- Get inventory
  SELECT * INTO v_inventory FROM inventories WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Inventory not found'));
  END IF;

  -- Calculate cargo usage
  v_cargo_used := COALESCE(v_inventory.ore, 0) + COALESCE(v_inventory.organics, 0) + 
                  COALESCE(v_inventory.goods, 0) + COALESCE(v_inventory.energy, 0);
  v_cargo_free := v_ship.cargo - v_cargo_used;

  -- Handle buy action
  IF p_action = 'buy' THEN
    -- Check if buying native commodity
    IF p_resource != v_port.kind THEN
      RETURN json_build_object('error', json_build_object('code','resource_not_allowed','message','Can only buy the port''s native commodity'));
    END IF;
    
    -- Check cargo capacity
    IF p_qty > v_cargo_free THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_cargo','message','Not enough cargo space'));
    END IF;
    
    -- Calculate price (0.90 * base price for native commodity)
    CASE p_resource
      WHEN 'ore' THEN v_unit_price := v_port.price_ore * 0.90;
      WHEN 'organics' THEN v_unit_price := v_port.price_organics * 0.90;
      WHEN 'goods' THEN v_unit_price := v_port.price_goods * 0.90;
      WHEN 'energy' THEN v_unit_price := v_port.price_energy * 0.90;
    END CASE;
    
    v_total := v_unit_price * p_qty;
    
    -- Check credits
    IF v_total > v_player_credits THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_credits','message','Not enough credits'));
    END IF;
    
    -- Check port stock
    CASE p_resource
      WHEN 'ore' THEN 
        IF p_qty > v_port.ore THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Not enough stock'));
        END IF;
      WHEN 'organics' THEN 
        IF p_qty > v_port.organics THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Not enough stock'));
        END IF;
      WHEN 'goods' THEN 
        IF p_qty > v_port.goods THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Not enough stock'));
        END IF;
      WHEN 'energy' THEN 
        IF p_qty > v_port.energy THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Not enough stock'));
        END IF;
    END CASE;
    
    -- Execute buy transaction
    UPDATE players SET credits = credits - v_total WHERE id = v_player_id;
    
    CASE p_resource
      WHEN 'ore' THEN 
        UPDATE inventories SET ore = ore + p_qty WHERE player_id = v_player_id;
        UPDATE ports SET ore = ore - p_qty WHERE id = p_port_id;
      WHEN 'organics' THEN 
        UPDATE inventories SET organics = organics + p_qty WHERE player_id = v_player_id;
        UPDATE ports SET organics = organics - p_qty WHERE id = p_port_id;
      WHEN 'goods' THEN 
        UPDATE inventories SET goods = goods + p_qty WHERE player_id = v_player_id;
        UPDATE ports SET goods = goods - p_qty WHERE id = p_port_id;
      WHEN 'energy' THEN 
        UPDATE inventories SET energy = energy + p_qty WHERE player_id = v_player_id;
        UPDATE ports SET energy = energy - p_qty WHERE id = p_port_id;
    END CASE;
    
    -- Log trade
    INSERT INTO trades (player_id, port_id, action, resource, quantity, unit_price, total_price)
    VALUES (v_player_id, p_port_id, 'buy', p_resource, p_qty, v_unit_price, v_total);
    
    RETURN json_build_object(
      'ok', true,
      'action', 'buy',
      'resource', p_resource,
      'quantity', p_qty,
      'unit_price', v_unit_price,
      'total_price', v_total,
      'credits_after', v_player_credits - v_total
    );
  END IF;

  -- Handle sell action
  IF p_action = 'sell' THEN
    -- Check if selling non-native commodity
    IF p_resource = v_port.kind THEN
      RETURN json_build_object('error', json_build_object('code','resource_not_allowed','message','Cannot sell the port''s native commodity here'));
    END IF;
    
    -- Check inventory
    CASE p_resource
      WHEN 'ore' THEN 
        IF p_qty > COALESCE(v_inventory.ore, 0) THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Not enough inventory'));
        END IF;
      WHEN 'organics' THEN 
        IF p_qty > COALESCE(v_inventory.organics, 0) THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Not enough inventory'));
        END IF;
      WHEN 'goods' THEN 
        IF p_qty > COALESCE(v_inventory.goods, 0) THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Not enough inventory'));
        END IF;
      WHEN 'energy' THEN 
        IF p_qty > COALESCE(v_inventory.energy, 0) THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Not enough inventory'));
        END IF;
    END CASE;
    
    -- Calculate price (1.10 * base price for non-native commodity)
    CASE p_resource
      WHEN 'ore' THEN v_unit_price := v_port.price_ore * 1.10;
      WHEN 'organics' THEN v_unit_price := v_port.price_organics * 1.10;
      WHEN 'goods' THEN v_unit_price := v_port.price_goods * 1.10;
      WHEN 'energy' THEN v_unit_price := v_port.price_energy * 1.10;
    END CASE;
    
    v_total := v_unit_price * p_qty;
    
    -- Execute sell transaction
    UPDATE players SET credits = credits + v_total WHERE id = v_player_id;
    
    CASE p_resource
      WHEN 'ore' THEN 
        UPDATE inventories SET ore = ore - p_qty WHERE player_id = v_player_id;
        UPDATE ports SET ore = ore + p_qty WHERE id = p_port_id;
      WHEN 'organics' THEN 
        UPDATE inventories SET organics = organics - p_qty WHERE player_id = v_player_id;
        UPDATE ports SET organics = organics + p_qty WHERE id = p_port_id;
      WHEN 'goods' THEN 
        UPDATE inventories SET goods = goods - p_qty WHERE player_id = v_player_id;
        UPDATE ports SET goods = goods + p_qty WHERE id = p_port_id;
      WHEN 'energy' THEN 
        UPDATE inventories SET energy = energy - p_qty WHERE player_id = v_player_id;
        UPDATE ports SET energy = energy + p_qty WHERE id = p_port_id;
    END CASE;
    
    -- Log trade
    INSERT INTO trades (player_id, port_id, action, resource, quantity, unit_price, total_price)
    VALUES (v_player_id, p_port_id, 'sell', p_resource, p_qty, v_unit_price, v_total);
    
    RETURN json_build_object(
      'ok', true,
      'action', 'sell',
      'resource', p_resource,
      'quantity', p_qty,
      'unit_price', v_unit_price,
      'total_price', v_total,
      'credits_after', v_player_credits + v_total
    );
  END IF;

  RETURN json_build_object('error', json_build_object('code','invalid_action','message','Invalid action'));
END;
$$;

-- 2. Fix game_trade_auto RPC function - Add universe_id parameter
CREATE OR REPLACE FUNCTION game_trade_auto(
  p_user_id UUID, 
  p_port UUID,
  p_universe_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_port RECORD;
  v_inv RECORD;
  pc TEXT; -- port commodity
  sell_price NUMERIC; -- native sell price (0.90 * base)
  buy_prices JSONB;   -- other resources buy price (1.10 * base)
  proceeds NUMERIC := 0;
  sold_ore INT := 0; sold_organics INT := 0; sold_goods INT := 0; sold_energy INT := 0;
  new_ore INT; new_organics INT; new_goods INT; new_energy INT;
  native_stock INT; native_price NUMERIC;
  credits_after NUMERIC;
  capacity INT; cargo_used INT; cargo_after INT; q INT := 0;
  native_key TEXT;
  err JSONB;
BEGIN
  -- Load player, ship, port - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT * INTO v_player FROM public.players WHERE user_id = p_user_id AND universe_id = p_universe_id FOR UPDATE;
  ELSE
    SELECT * INTO v_player FROM public.players WHERE user_id = p_user_id FOR UPDATE;
  END IF;
  
  IF NOT FOUND THEN 
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Player not found')); 
  END IF;

  SELECT * INTO v_ship FROM public.ships WHERE player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN 
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Ship not found')); 
  END IF;

  SELECT p.*, s.number as sector_number INTO v_port
  FROM public.ports p
  JOIN public.sectors s ON s.id = p.sector_id
  WHERE p.id = p_port FOR UPDATE;
  IF NOT FOUND THEN 
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Port not found')); 
  END IF;
  IF v_port.kind = 'special' THEN 
    RETURN jsonb_build_object('error', jsonb_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.')); 
  END IF;

  -- Validate co-location
  IF v_player.current_sector <> v_port.sector_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code','wrong_sector','message','Player not in port sector'));
  END IF;

  pc := v_port.kind; -- ore|organics|goods|energy

  -- Get inventory
  SELECT * INTO v_inv FROM public.inventories WHERE player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN 
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Inventory not found')); 
  END IF;

  -- Calculate cargo capacity
  capacity := v_ship.cargo;
  cargo_used := COALESCE(v_inv.ore, 0) + COALESCE(v_inv.organics, 0) + COALESCE(v_inv.goods, 0) + COALESCE(v_inv.energy, 0);
  
  -- Auto-sell all non-native resources
  IF pc != 'ore' AND COALESCE(v_inv.ore, 0) > 0 THEN
    sold_ore := v_inv.ore;
    proceeds := proceeds + (sold_ore * v_port.price_ore * 1.10);
    UPDATE public.inventories SET ore = 0 WHERE player_id = v_player.id;
    UPDATE public.ports SET ore = ore + sold_ore WHERE id = p_port;
  END IF;
  
  IF pc != 'organics' AND COALESCE(v_inv.organics, 0) > 0 THEN
    sold_organics := v_inv.organics;
    proceeds := proceeds + (sold_organics * v_port.price_organics * 1.10);
    UPDATE public.inventories SET organics = 0 WHERE player_id = v_player.id;
    UPDATE public.ports SET organics = organics + sold_organics WHERE id = p_port;
  END IF;
  
  IF pc != 'goods' AND COALESCE(v_inv.goods, 0) > 0 THEN
    sold_goods := v_inv.goods;
    proceeds := proceeds + (sold_goods * v_port.price_goods * 1.10);
    UPDATE public.inventories SET goods = 0 WHERE player_id = v_player.id;
    UPDATE public.ports SET goods = goods + sold_goods WHERE id = p_port;
  END IF;
  
  IF pc != 'energy' AND COALESCE(v_inv.energy, 0) > 0 THEN
    sold_energy := v_inv.energy;
    proceeds := proceeds + (sold_energy * v_port.price_energy * 1.10);
    UPDATE public.inventories SET energy = 0 WHERE player_id = v_player.id;
    UPDATE public.ports SET energy = energy + sold_energy WHERE id = p_port;
  END IF;

  -- Update player credits
  UPDATE public.players SET credits = credits + proceeds WHERE id = v_player.id;
  credits_after := v_player.credits + proceeds;

  -- Calculate cargo free after sells
  cargo_after := capacity - 0; -- All inventory sold

  -- Auto-buy native commodity
  CASE pc
    WHEN 'ore' THEN 
      native_price := v_port.price_ore * 0.90;
      native_stock := v_port.ore;
    WHEN 'organics' THEN 
      native_price := v_port.price_organics * 0.90;
      native_stock := v_port.organics;
    WHEN 'goods' THEN 
      native_price := v_port.price_goods * 0.90;
      native_stock := v_port.goods;
    WHEN 'energy' THEN 
      native_price := v_port.price_energy * 0.90;
      native_stock := v_port.energy;
  END CASE;

  q := LEAST(native_stock, FLOOR(credits_after / native_price), cargo_after);
  
  IF q > 0 THEN
    CASE pc
      WHEN 'ore' THEN 
        UPDATE public.inventories SET ore = ore + q WHERE player_id = v_player.id;
        UPDATE public.ports SET ore = ore - q WHERE id = p_port;
      WHEN 'organics' THEN 
        UPDATE public.inventories SET organics = organics + q WHERE player_id = v_player.id;
        UPDATE public.ports SET organics = organics - q WHERE id = p_port;
      WHEN 'goods' THEN 
        UPDATE public.inventories SET goods = goods + q WHERE player_id = v_player.id;
        UPDATE public.ports SET goods = goods - q WHERE id = p_port;
      WHEN 'energy' THEN 
        UPDATE public.inventories SET energy = energy + q WHERE player_id = v_player.id;
        UPDATE public.ports SET energy = energy - q WHERE id = p_port;
    END CASE;
    
    UPDATE public.players SET credits = credits - (q * native_price) WHERE id = v_player.id;
  END IF;

  -- Get final inventory
  SELECT ore, organics, goods, energy INTO new_ore, new_organics, new_goods, new_energy
  FROM public.inventories WHERE player_id = v_player.id;

  RETURN jsonb_build_object(
    'ok', true,
    'sold', jsonb_build_object(
      'ore', sold_ore,
      'organics', sold_organics,
      'goods', sold_goods,
      'energy', sold_energy
    ),
    'bought', jsonb_build_object(
      'resource', pc,
      'qty', q
    ),
    'credits_after', credits_after - (q * native_price),
    'inventory_after', jsonb_build_object(
      'ore', new_ore,
      'organics', new_organics,
      'goods', new_goods,
      'energy', new_energy
    )
  );
END;
$$;

-- 3. Fix game_ship_upgrade RPC function - Add universe_id parameter
CREATE OR REPLACE FUNCTION game_ship_upgrade(
  p_user_id UUID,
  p_attr TEXT,
  p_universe_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_cost INTEGER;
  v_result JSONB;
BEGIN
  -- Validate attribute
  IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
  END IF;

  -- Get player data - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT p.* INTO v_player
    FROM players p
    WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id
    FOR UPDATE;
  ELSE
    SELECT p.* INTO v_player
    FROM players p
    WHERE p.user_id = p_user_id
    FOR UPDATE;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship data
  SELECT s.* INTO v_ship
  FROM ships s
  WHERE s.player_id = v_player.id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  -- Check if player is at a Special port
  IF NOT EXISTS (
    SELECT 1 FROM ports p 
    JOIN sectors s ON p.sector_id = s.id 
    WHERE s.id = v_player.current_sector AND p.kind = 'special'
  ) THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'wrong_port', 'message', 'Must be at a Special port to upgrade'));
  END IF;

  -- Calculate cost
  CASE p_attr
    WHEN 'engine' THEN v_cost := 500 * (v_ship.engine_lvl + 1);
    WHEN 'computer' THEN v_cost := 1000 * (v_ship.comp_lvl + 1);
    WHEN 'sensors' THEN v_cost := 800 * (v_ship.sensor_lvl + 1);
    WHEN 'shields' THEN v_cost := 1500 * (v_ship.shield_lvl + 1);
    WHEN 'hull' THEN v_cost := 2000 * (v_ship.hull_lvl + 1);
  END CASE;

  -- Check if player has enough credits
  IF v_player.credits < v_cost THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
  END IF;

  -- Perform upgrade
  CASE p_attr
    WHEN 'engine' THEN
      UPDATE ships SET engine_lvl = engine_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'computer' THEN
      UPDATE ships SET comp_lvl = comp_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'sensors' THEN
      UPDATE ships SET sensor_lvl = sensor_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'shields' THEN
      UPDATE ships SET 
        shield_lvl = shield_lvl + 1,
        shield = shield_max
      WHERE player_id = v_player.id;
    WHEN 'hull' THEN
      UPDATE ships SET 
        hull_lvl = hull_lvl + 1,
        hull = hull_max,
        cargo = CASE 
          WHEN hull_lvl + 1 = 1 THEN 1000
          WHEN hull_lvl + 1 = 2 THEN 3500
          WHEN hull_lvl + 1 = 3 THEN 7224
          WHEN hull_lvl + 1 = 4 THEN 10000
          WHEN hull_lvl + 1 = 5 THEN 13162
          ELSE FLOOR(1000 * POWER(hull_lvl + 1, 1.8))
        END
      WHERE player_id = v_player.id;
  END CASE;

  -- Deduct credits
  UPDATE players SET credits = credits - v_cost WHERE id = v_player.id;

  RETURN jsonb_build_object(
    'ok', true,
    'attribute', p_attr,
    'cost', v_cost,
    'credits_after', v_player.credits - v_cost
  );
END;
$$;

-- 4. Fix game_planet_claim RPC function - Add universe_id parameter
CREATE OR REPLACE FUNCTION game_planet_claim(
    p_user_id UUID,
    p_sector_number INT,
    p_name TEXT DEFAULT 'Colony',
    p_universe_id UUID DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_player_id UUID;
    v_sector_id UUID;
    v_universe_id UUID;
    v_planet_id UUID;
BEGIN
    -- Find player by auth user_id - filter by universe if provided
    IF p_universe_id IS NOT NULL THEN
        SELECT p.id, s.universe_id
        INTO v_player_id, v_universe_id
        FROM players p
        JOIN sectors s ON p.current_sector = s.id
        WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
    ELSE
        SELECT p.id, s.universe_id
        INTO v_player_id, v_universe_id
        FROM players p
        JOIN sectors s ON p.current_sector = s.id
        WHERE p.user_id = p_user_id;
    END IF;

    IF v_player_id IS NULL THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
    END IF;

    -- Find sector
    SELECT id INTO v_sector_id
    FROM sectors
    WHERE universe_id = v_universe_id AND number = p_sector_number;

    IF v_sector_id IS NULL THEN
        RETURN json_build_object('error', json_build_object('code', 'sector_not_found', 'message', 'Sector not found'));
    END IF;

    -- Check if player is in the correct sector
    IF NOT EXISTS (
        SELECT 1 FROM players 
        WHERE id = v_player_id AND current_sector = v_sector_id
    ) THEN
        RETURN json_build_object('error', json_build_object('code', 'wrong_sector', 'message', 'Player not in target sector'));
    END IF;

    -- Check if planet already exists
    IF EXISTS (
        SELECT 1 FROM planets 
        WHERE sector_id = v_sector_id
    ) THEN
        RETURN json_build_object('error', json_build_object('code', 'planet_exists', 'message', 'Planet already exists in this sector'));
    END IF;

    -- Create planet
    INSERT INTO planets (sector_id, name, owner_player_id)
    VALUES (v_sector_id, p_name, v_player_id)
    RETURNING id INTO v_planet_id;

    RETURN json_build_object(
        'ok', true,
        'planet_id', v_planet_id,
        'name', p_name,
        'sector_number', p_sector_number
    );
END;
$$ LANGUAGE plpgsql;
