-- Fix game_trade_auto function to use ships table instead of inventories
-- Run once in Supabase SQL Editor

-- Drop existing functions
DROP FUNCTION IF EXISTS public.game_trade_auto(uuid, uuid);
DROP FUNCTION IF EXISTS public.game_trade_auto(uuid, uuid, uuid);

-- Create updated game_trade_auto function that uses ships table
CREATE OR REPLACE FUNCTION public.game_trade_auto(
  p_user_id UUID,
  p_port UUID,
  p_universe_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players;
  v_ship ships;
  v_port ports;
  pc text; -- port commodity
  sell_price numeric; -- native sell price (0.90 * base)
  proceeds numeric := 0;
  sold_ore int := 0; 
  sold_organics int := 0; 
  sold_goods int := 0; 
  sold_energy int := 0;
  new_ore int; 
  new_organics int; 
  new_goods int; 
  new_energy int;
  native_stock int; 
  native_price numeric;
  credits_after numeric;
  capacity int; 
  cargo_used int; 
  q int := 0;
BEGIN
  -- Load player, ship, port with universe validation
  SELECT * INTO v_player FROM players WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN 
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Player not found')); 
  END IF;

  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN 
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Ship not found')); 
  END IF;

  SELECT p.* INTO v_port
  FROM ports p
  WHERE p.id = p_port FOR UPDATE;
  
  IF NOT FOUND THEN 
    RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Port not found')); 
  END IF;
  
  IF v_port.kind = 'special' THEN 
    RETURN jsonb_build_object('error', jsonb_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.')); 
  END IF;

  -- Universe validation - only validate if universe_id is provided and doesn't match
  IF p_universe_id IS NOT NULL AND v_player.universe_id != p_universe_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code','universe_mismatch','message','Port not in player universe'));
  END IF;
  
  -- Additional validation: ensure port is in the same universe as player
  IF v_player.universe_id != v_sector.universe_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code','universe_mismatch','message','Port not in player universe'));
  END IF;

  -- Validate co-location
  IF v_player.current_sector <> v_port.sector_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code','wrong_sector','message','Player not in port sector'));
  END IF;

  pc := v_port.kind; -- ore|organics|goods|energy

  -- Enhanced pricing with dynamic stock-based multipliers
  native_price := CASE pc
    WHEN 'ore' THEN v_port.price_ore * calculate_price_multiplier(v_port.ore, v_port.kind)
    WHEN 'organics' THEN v_port.price_organics * calculate_price_multiplier(v_port.organics, v_port.kind)
    WHEN 'goods' THEN v_port.price_goods * calculate_price_multiplier(v_port.goods, v_port.kind)
    WHEN 'energy' THEN v_port.price_energy * calculate_price_multiplier(v_port.energy, v_port.kind)
  END;
  sell_price := native_price * 0.90; -- player buys from port at 0.90 * dynamic price

  -- Get current ship inventory
  new_ore := v_ship.ore;
  new_organics := v_ship.organics;
  new_goods := v_ship.goods;
  new_energy := v_ship.energy;

  -- Sell non-native resources with enhanced dynamic pricing
  IF pc <> 'ore' AND v_ship.ore > 0 THEN
    proceeds := proceeds + (v_port.price_ore * calculate_price_multiplier(v_port.ore, v_port.kind) * 1.10) * v_ship.ore;
    sold_ore := v_ship.ore;
    new_ore := 0;
    v_port.ore := v_port.ore + sold_ore;
  END IF;
  
  IF pc <> 'organics' AND v_ship.organics > 0 THEN
    proceeds := proceeds + (v_port.price_organics * calculate_price_multiplier(v_port.organics, v_port.kind) * 1.10) * v_ship.organics;
    sold_organics := v_ship.organics;
    new_organics := 0;
    v_port.organics := v_port.organics + sold_organics;
  END IF;
  
  IF pc <> 'goods' AND v_ship.goods > 0 THEN
    proceeds := proceeds + (v_port.price_goods * calculate_price_multiplier(v_port.goods, v_port.kind) * 1.10) * v_ship.goods;
    sold_goods := v_ship.goods;
    new_goods := 0;
    v_port.goods := v_port.goods + sold_goods;
  END IF;
  
  IF pc <> 'energy' AND v_ship.energy > 0 THEN
    proceeds := proceeds + (v_port.price_energy * calculate_price_multiplier(v_port.energy, v_port.kind) * 1.10) * v_ship.energy;
    sold_energy := v_ship.energy;
    new_energy := 0;
    v_port.energy := v_port.energy + sold_energy;
  END IF;

  -- Credits and capacity after sells
  credits_after := v_player.credits + proceeds;
  cargo_used := new_ore + new_organics + new_goods + new_energy;
  capacity := v_ship.cargo - cargo_used;

  -- Native stock and buy quantity
  native_stock := CASE pc
    WHEN 'ore' THEN v_port.ore
    WHEN 'organics' THEN v_port.organics
    WHEN 'goods' THEN v_port.goods
    WHEN 'energy' THEN v_port.energy
  END;

  q := LEAST(native_stock, FLOOR(credits_after / sell_price)::int, GREATEST(capacity, 0));
  IF q < 0 THEN q := 0; END IF;

  -- Apply buy
  IF q > 0 THEN
    credits_after := credits_after - (q * sell_price);
    CASE pc
      WHEN 'ore' THEN BEGIN 
        new_ore := new_ore + q; 
        v_port.ore := v_port.ore - q; 
      END;
      WHEN 'organics' THEN BEGIN 
        new_organics := new_organics + q; 
        v_port.organics := v_port.organics - q; 
      END;
      WHEN 'goods' THEN BEGIN 
        new_goods := new_goods + q; 
        v_port.goods := v_port.goods - q; 
      END;
      WHEN 'energy' THEN BEGIN 
        new_energy := new_energy + q; 
        v_port.energy := v_port.energy - q; 
      END;
    END CASE;
  END IF;

  -- Persist changes
  UPDATE players
  SET credits = credits_after
  WHERE id = v_player.id;

  UPDATE ships
  SET ore = new_ore,
      organics = new_organics,
      goods = new_goods,
      energy = new_energy
  WHERE player_id = v_player.id;

  UPDATE ports SET
    ore = v_port.ore,
    organics = v_port.organics,
    goods = v_port.goods,
    energy = v_port.energy
  WHERE id = p_port;

  RETURN jsonb_build_object(
    'sold', jsonb_build_object('ore', sold_ore, 'organics', sold_organics, 'goods', sold_goods, 'energy', sold_energy),
    'bought', jsonb_build_object('resource', pc, 'qty', q),
    'credits', credits_after,
    'inventory_after', jsonb_build_object('ore', new_ore, 'organics', new_organics, 'goods', new_goods, 'energy', new_energy),
    'port_stock_after', jsonb_build_object('ore', v_port.ore, 'organics', v_port.organics, 'goods', v_port.goods, 'energy', v_port.energy),
    'prices', jsonb_build_object('pcSell', sell_price)
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.game_trade_auto(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_trade_auto(uuid, uuid, uuid) TO service_role;
