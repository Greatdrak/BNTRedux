-- Fix trade functions to work with updated schema
-- Credits moved from players to ships, inventories merged into ships

-- Drop existing functions first
DROP FUNCTION IF EXISTS public.game_trade(UUID, UUID, TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.game_trade(UUID, UUID, TEXT, TEXT, INTEGER, UUID);
DROP FUNCTION IF EXISTS public.game_trade_auto(UUID, UUID);
DROP FUNCTION IF EXISTS public.game_trade_auto(UUID, UUID, UUID);

-- Drop all existing versions of calculate_price_multiplier to avoid conflicts
DROP FUNCTION IF EXISTS public.calculate_price_multiplier(integer);
DROP FUNCTION IF EXISTS public.calculate_price_multiplier(integer, integer);

-- Ensure calculate_price_multiplier function exists
CREATE OR REPLACE FUNCTION public.calculate_price_multiplier(current_stock integer, base_stock integer DEFAULT 1000000000) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  -- Price range: 0.8x to 1.5x based on stock levels
  -- Low stock = higher prices, high stock = lower prices
  -- Use logarithmic scaling to make small changes negligible for low-level players
  
  IF current_stock <= 0 THEN
    RETURN 1.5; -- Maximum price when out of stock
  END IF;
  
  -- Logarithmic scaling: log10(stock/base_stock)
  -- This means 10% stock = ~1.4x price, 50% stock = ~1.0x price, 200% stock = ~0.8x price
  DECLARE
    stock_ratio NUMERIC := current_stock::NUMERIC / base_stock;
    log_factor NUMERIC := LOG(10, GREATEST(stock_ratio, 0.1)); -- Clamp to avoid log(0)
    multiplier NUMERIC;
  BEGIN
    -- Scale log factor to price range (0.8 to 1.5)
    multiplier := 1.5 - (log_factor + 1) * 0.35; -- log(0.1) ≈ -1, log(10) ≈ 1
    multiplier := GREATEST(0.8, LEAST(1.5, multiplier)); -- Clamp to range
    RETURN multiplier;
  END;
END;
$$;

-- Update game_trade function (with universe_id parameter)
CREATE OR REPLACE FUNCTION public.game_trade(
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
  v_ship_credits BIGINT;
  v_player_current_sector UUID;
  v_ship RECORD;
  v_port RECORD;
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

  SELECT * INTO v_port FROM ports WHERE id = p_port;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Port not found'));
  END IF;
  IF v_port.sector_id != v_player_current_sector THEN
    RETURN json_build_object('error', json_build_object('code','wrong_sector','message','Player not in port sector'));
  END IF;

  IF v_port.kind = 'special' THEN
    RETURN json_build_object('error', json_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.'));
  END IF;

  -- Calculate cargo usage
  v_cargo_used := COALESCE(v_ship.ore, 0) + COALESCE(v_ship.organics, 0) + COALESCE(v_ship.goods, 0) + COALESCE(v_ship.energy, 0) + COALESCE(v_ship.colonists, 0);
  v_cargo_free := v_ship.cargo - v_cargo_used;

  -- Get unit price based on resource
  CASE p_resource
    WHEN 'ore' THEN v_unit_price := v_port.price_ore * calculate_price_multiplier(v_port.ore, 1000000000);
    WHEN 'organics' THEN v_unit_price := v_port.price_organics * calculate_price_multiplier(v_port.organics, 1000000000);
    WHEN 'goods' THEN v_unit_price := v_port.price_goods * calculate_price_multiplier(v_port.goods, 1000000000);
    WHEN 'energy' THEN v_unit_price := v_port.price_energy * calculate_price_multiplier(v_port.energy, 1000000000);
  END CASE;

  IF p_action = 'buy' THEN
    -- Buying from port
    v_total := v_unit_price * p_qty;
    
    -- Check if player has enough credits
    IF v_ship.credits < v_total THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_credits','message','Insufficient credits'));
    END IF;
    
    -- Check cargo space
    IF v_cargo_free < p_qty THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_cargo','message','Insufficient cargo space'));
    END IF;
    
    -- Check port stock
    CASE p_resource
      WHEN 'ore' THEN IF v_port.ore < p_qty THEN RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Port has insufficient stock')); END IF;
      WHEN 'organics' THEN IF v_port.organics < p_qty THEN RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Port has insufficient stock')); END IF;
      WHEN 'goods' THEN IF v_port.goods < p_qty THEN RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Port has insufficient stock')); END IF;
      WHEN 'energy' THEN IF v_port.energy < p_qty THEN RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Port has insufficient stock')); END IF;
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
    WHERE id = p_port;
    
  ELSE -- sell
    -- Selling to port
    v_total := v_unit_price * 0.9 * p_qty; -- Port buys at 90% of sell price
    
    -- Check if player has enough resources
    CASE p_resource
      WHEN 'ore' THEN IF COALESCE(v_ship.ore, 0) < p_qty THEN RETURN json_build_object('error', json_build_object('code','insufficient_resources','message','Insufficient resources')); END IF;
      WHEN 'organics' THEN IF COALESCE(v_ship.organics, 0) < p_qty THEN RETURN json_build_object('error', json_build_object('code','insufficient_resources','message','Insufficient resources')); END IF;
      WHEN 'goods' THEN IF COALESCE(v_ship.goods, 0) < p_qty THEN RETURN json_build_object('error', json_build_object('code','insufficient_resources','message','Insufficient resources')); END IF;
      WHEN 'energy' THEN IF COALESCE(v_ship.energy, 0) < p_qty THEN RETURN json_build_object('error', json_build_object('code','insufficient_resources','message','Insufficient resources')); END IF;
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
    WHERE id = p_port;
  END IF;

  -- Return success result
  RETURN json_build_object(
    'success', true,
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

-- Update game_trade_auto function (with universe_id parameter)
CREATE OR REPLACE FUNCTION public.game_trade_auto(
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
  -- Debug logging
  RAISE NOTICE 'game_trade_auto called with: user_id=%, port=%, universe_id=%', p_user_id, p_port, p_universe_id;
  
  -- Load player, ship, port - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT * INTO v_player FROM public.players WHERE user_id = p_user_id AND universe_id = p_universe_id FOR UPDATE;
  ELSE
    SELECT * INTO v_player FROM public.players WHERE user_id = p_user_id FOR UPDATE;
  END IF;
  
  IF NOT FOUND THEN 
    RAISE NOTICE 'Player not found for user_id=% universe_id=%', p_user_id, p_universe_id;
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Player not found')); 
  END IF;
  
  RAISE NOTICE 'Found player: id=%, handle=%', v_player.id, v_player.handle;

  SELECT * INTO v_ship FROM public.ships WHERE player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN 
    RAISE NOTICE 'Ship not found for player_id=%', v_player.id;
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Ship not found')); 
  END IF;
  
  RAISE NOTICE 'Found ship: id=%, name=%, credits=%', v_ship.id, v_ship.name, v_ship.credits;

  SELECT p.*, s.number as sector_number INTO v_port
  FROM public.ports p
  JOIN public.sectors s ON s.id = p.sector_id
  WHERE p.id = p_port FOR UPDATE;
  IF NOT FOUND THEN 
    RAISE NOTICE 'Port not found for port_id=%', p_port;
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Port not found')); 
  END IF;
  
  RAISE NOTICE 'Found port: id=%, kind=%, sector=%', v_port.id, v_port.kind, v_port.sector_number;
  
  IF v_port.kind = 'special' THEN 
    RAISE NOTICE 'Cannot auto-trade at special port';
    RETURN jsonb_build_object('error', jsonb_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.')); 
  END IF;

  -- Validate co-location
  RAISE NOTICE 'Checking co-location: player_sector=%, port_sector=%', v_player.current_sector, v_port.sector_id;
  IF v_player.current_sector <> v_port.sector_id THEN
    RAISE NOTICE 'Player not in port sector';
    RETURN jsonb_build_object('error', jsonb_build_object('code','wrong_sector','message','Player not in port sector'));
  END IF;

  pc := v_port.kind; -- ore|organics|goods|energy
  native_key := pc;
  
  RAISE NOTICE 'Port commodity: %, native_key: %', pc, native_key;

  -- pricing with dynamic stock-based multipliers
  native_price := case pc
    when 'ore' then v_port.price_ore * calculate_price_multiplier(v_port.ore, 1000000000)
    when 'organics' then v_port.price_organics * calculate_price_multiplier(v_port.organics, 1000000000)
    when 'goods' then v_port.price_goods * calculate_price_multiplier(v_port.goods, 1000000000)
    when 'energy' then v_port.price_energy * calculate_price_multiplier(v_port.energy, 1000000000)
  end;
  sell_price := native_price * 0.90; -- player buys from port at 0.90 * dynamic price
  
  RAISE NOTICE 'Pricing: native_price=%, sell_price=%', native_price, sell_price;

  -- sell non-native resources at 1.10 * base price
  buy_prices := jsonb_build_object(
    'ore', v_port.price_ore * 1.10 * calculate_price_multiplier(v_port.ore, 1000000000),
    'organics', v_port.price_organics * 1.10 * calculate_price_multiplier(v_port.organics, 1000000000),
    'goods', v_port.price_goods * 1.10 * calculate_price_multiplier(v_port.goods, 1000000000),
    'energy', v_port.price_energy * 1.10 * calculate_price_multiplier(v_port.energy, 1000000000)
  );

  -- calculate cargo capacity and usage
  capacity := v_ship.cargo;
  cargo_used := COALESCE(v_ship.ore, 0) + COALESCE(v_ship.organics, 0) + COALESCE(v_ship.goods, 0) + COALESCE(v_ship.energy, 0) + COALESCE(v_ship.colonists, 0);
  cargo_after := cargo_used;

  -- sell non-native resources
  IF pc <> 'ore' AND COALESCE(v_ship.ore, 0) > 0 THEN
    q := LEAST(v_ship.ore, capacity - cargo_after);
    IF q > 0 THEN
      proceeds := proceeds + (q * (buy_prices->>'ore')::numeric);
      sold_ore := q;
      cargo_after := cargo_after - q;
    END IF;
  END IF;

  IF pc <> 'organics' AND COALESCE(v_ship.organics, 0) > 0 THEN
    q := LEAST(v_ship.organics, capacity - cargo_after);
    IF q > 0 THEN
      proceeds := proceeds + (q * (buy_prices->>'organics')::numeric);
      sold_organics := q;
      cargo_after := cargo_after - q;
    END IF;
  END IF;

  IF pc <> 'goods' AND COALESCE(v_ship.goods, 0) > 0 THEN
    q := LEAST(v_ship.goods, capacity - cargo_after);
    IF q > 0 THEN
      proceeds := proceeds + (q * (buy_prices->>'goods')::numeric);
      sold_goods := q;
      cargo_after := cargo_after - q;
    END IF;
  END IF;

  IF pc <> 'energy' AND COALESCE(v_ship.energy, 0) > 0 THEN
    q := LEAST(v_ship.energy, capacity - cargo_after);
    IF q > 0 THEN
      proceeds := proceeds + (q * (buy_prices->>'energy')::numeric);
      sold_energy := q;
      cargo_after := cargo_after - q;
    END IF;
  END IF;

  -- buy native resource with available cargo space and credits
  native_stock := case pc
    when 'ore' then v_port.ore
    when 'organics' then v_port.organics
    when 'goods' then v_port.goods
    when 'energy' then v_port.energy
  end;

  q := LEAST(
    native_stock,
    capacity - cargo_after,
    FLOOR(v_ship.credits / sell_price)
  );

  IF q > 0 THEN
    -- update ship inventory and credits
    UPDATE public.ships SET
      credits = credits - (q * sell_price),
      ore = CASE WHEN pc = 'ore' THEN ore + q ELSE ore END,
      organics = CASE WHEN pc = 'organics' THEN organics + q ELSE organics END,
      goods = CASE WHEN pc = 'goods' THEN goods + q ELSE goods END,
      energy = CASE WHEN pc = 'energy' THEN energy + q ELSE energy END
    WHERE id = v_ship.id;

    -- update port stock and credits
    UPDATE public.ports SET
      ore = CASE WHEN pc = 'ore' THEN ore - q ELSE ore END,
      organics = CASE WHEN pc = 'organics' THEN organics - q ELSE organics END,
      goods = CASE WHEN pc = 'goods' THEN goods - q ELSE goods END,
      energy = CASE WHEN pc = 'energy' THEN energy - q ELSE energy END,
      credits = credits + (q * sell_price)
    WHERE id = p_port;
  END IF;

  -- update ship credits with proceeds from selling
  IF proceeds > 0 THEN
    UPDATE public.ships SET
      credits = credits + proceeds,
      ore = ore - sold_ore,
      organics = organics - sold_organics,
      goods = goods - sold_goods,
      energy = energy - sold_energy
    WHERE id = v_ship.id;

    -- update port stock and credits
    UPDATE public.ports SET
      ore = ore + sold_ore,
      organics = organics + sold_organics,
      goods = goods + sold_goods,
      energy = energy + sold_energy,
      credits = credits - proceeds
    WHERE id = p_port;
  END IF;

  -- get final ship state
  SELECT credits INTO credits_after FROM public.ships WHERE id = v_ship.id;
  
  RAISE NOTICE 'Auto-trade completed: proceeds=%, credits_after=%', proceeds, credits_after;

  RETURN jsonb_build_object(
    'success', true,
    'port_commodity', pc,
    'sold', jsonb_build_object(
      'ore', sold_ore,
      'organics', sold_organics,
      'goods', sold_goods,
      'energy', sold_energy
    ),
    'bought', jsonb_build_object(
      pc, q
    ),
    'proceeds', proceeds,
    'credits_after', credits_after,
    'cargo_used_before', cargo_used,
    'cargo_used_after', cargo_after + q
  );

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Exception in game_trade_auto: %', SQLERRM;
    RETURN jsonb_build_object('error', jsonb_build_object('code','internal_error','message','Internal server error: ' || SQLERRM));
END;
$$;
