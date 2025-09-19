-- Comprehensive update to move credits from players to ships across all functions and APIs
-- This migration updates all RPC functions and ensures consistency

-- First, let's check if we need to update the game_trade function
-- The function should already be using ships table, but let's make sure credits are handled properly

-- Update game_trade function to ensure it uses ship credits
DROP FUNCTION IF EXISTS public.game_trade(uuid, uuid, text, text, integer, uuid);

CREATE OR REPLACE FUNCTION public.game_trade(
  p_user_id uuid,
  p_port_id uuid,
  p_action text,
  p_resource text,
  p_qty integer,
  p_universe_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid;
  v_ship_id uuid;
  v_port_record RECORD;
  v_ship_record RECORD;
  v_cost bigint;
  v_available_qty integer;
  v_cargo_space integer;
  v_result json;
BEGIN
  -- Get player and ship IDs
  SELECT p.id, s.id INTO v_player_id, v_ship_id
  FROM players p
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id 
    AND (p_universe_id IS NULL OR p.universe_id = p_universe_id);
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
  END IF;
  
  -- Get port data
  SELECT * INTO v_port_record
  FROM ports
  WHERE id = p_port_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code', 'port_not_found', 'message', 'Port not found'));
  END IF;
  
  -- Get ship data (including credits)
  SELECT * INTO v_ship_record
  FROM ships
  WHERE id = v_ship_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code', 'ship_not_found', 'message', 'Ship not found'));
  END IF;
  
  -- Calculate cost and validate trade
  IF p_action = 'buy' THEN
    v_cost := p_qty * v_port_record.price;
    
    -- Check if player has enough credits (from ship)
    IF v_ship_record.credits < v_cost THEN
      RETURN json_build_object('error', json_build_object('code', 'insufficient_credits', 'message', 'Insufficient credits'));
    END IF;
    
    -- Check cargo space
    v_cargo_space := v_ship_record.cargo - (v_ship_record.ore + v_ship_record.organics + v_ship_record.goods + v_ship_record.energy);
    IF v_cargo_space < p_qty THEN
      RETURN json_build_object('error', json_build_object('code', 'insufficient_cargo', 'message', 'Insufficient cargo space'));
    END IF;
    
    -- Check port stock
    IF v_port_record.stock < p_qty THEN
      RETURN json_build_object('error', json_build_object('code', 'insufficient_stock', 'message', 'Insufficient port stock'));
    END IF;
    
    -- Execute buy transaction
    UPDATE ships 
    SET 
      credits = credits - v_cost,
      ore = CASE WHEN p_resource = 'ore' THEN ore + p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics + p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods + p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy + p_qty ELSE energy END
    WHERE id = v_ship_id;
    
    UPDATE ports 
    SET stock = stock - p_qty
    WHERE id = p_port_id;
    
  ELSIF p_action = 'sell' THEN
    -- Check if player has enough resources
    v_available_qty := CASE p_resource
      WHEN 'ore' THEN v_ship_record.ore
      WHEN 'organics' THEN v_ship_record.organics
      WHEN 'goods' THEN v_ship_record.goods
      WHEN 'energy' THEN v_ship_record.energy
    END;
    
    IF v_available_qty < p_qty THEN
      RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Insufficient resources'));
    END IF;
    
    v_cost := p_qty * v_port_record.price;
    
    -- Execute sell transaction
    UPDATE ships 
    SET 
      credits = credits + v_cost,
      ore = CASE WHEN p_resource = 'ore' THEN ore - p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics - p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods - p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy - p_qty ELSE energy END
    WHERE id = v_ship_id;
    
    UPDATE ports 
    SET stock = stock + p_qty
    WHERE id = p_port_id;
  END IF;
  
  -- Return success result
  RETURN json_build_object(
    'success', true,
    'action', p_action,
    'resource', p_resource,
    'quantity', p_qty,
    'cost', v_cost,
    'remaining_credits', (SELECT credits FROM ships WHERE id = v_ship_id)
  );
END;
$$;

-- Update purchase_special_port_items function to use ship credits
DROP FUNCTION IF EXISTS public.purchase_special_port_items(uuid, jsonb);

CREATE OR REPLACE FUNCTION public.purchase_special_port_items(
  p_player_id uuid,
  p_purchases jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  purchase_item jsonb;
  total_cost bigint := 0;
  item_cost bigint;
  ship_credits bigint;
  remaining_credits bigint;
BEGIN
  -- Get current ship credits
  SELECT credits INTO ship_credits
  FROM ships
  WHERE player_id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Ship not found');
  END IF;
  
  -- Calculate total cost
  FOR purchase_item IN SELECT * FROM jsonb_array_elements(p_purchases)
  LOOP
    item_cost := (purchase_item->>'quantity')::integer * (purchase_item->>'price')::integer;
    total_cost := total_cost + item_cost;
  END LOOP;
  
  -- Check if player has enough credits
  IF ship_credits < total_cost THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient credits');
  END IF;
  
  -- Process each purchase
  FOR purchase_item IN SELECT * FROM jsonb_array_elements(p_purchases)
  LOOP
    item_cost := (purchase_item->>'quantity')::integer * (purchase_item->>'price')::integer;
    
    -- Update ship based on item type
    IF purchase_item->>'type' = 'upgrade' THEN
      -- Handle upgrades (this would need to be expanded based on upgrade types)
      UPDATE ships 
      SET credits = credits - item_cost
      WHERE player_id = p_player_id;
    ELSIF purchase_item->>'type' = 'device' THEN
      -- Handle device purchases
      UPDATE ships 
      SET 
        credits = credits - item_cost,
        device_space_beacons = CASE WHEN purchase_item->>'item' = 'space_beacons' 
          THEN device_space_beacons + (purchase_item->>'quantity')::integer 
          ELSE device_space_beacons END,
        device_warp_editors = CASE WHEN purchase_item->>'item' = 'warp_editors' 
          THEN device_warp_editors + (purchase_item->>'quantity')::integer 
          ELSE device_warp_editors END,
        device_genesis_torpedoes = CASE WHEN purchase_item->>'item' = 'genesis_torpedoes' 
          THEN device_genesis_torpedoes + (purchase_item->>'quantity')::integer 
          ELSE device_genesis_torpedoes END,
        device_mine_deflectors = CASE WHEN purchase_item->>'item' = 'mine_deflectors' 
          THEN device_mine_deflectors + (purchase_item->>'quantity')::integer 
          ELSE device_mine_deflectors END,
        device_emergency_warp = CASE WHEN purchase_item->>'item' = 'emergency_warp' 
          THEN true ELSE device_emergency_warp END,
        device_escape_pod = CASE WHEN purchase_item->>'item' = 'escape_pod' 
          THEN true ELSE device_escape_pod END,
        device_fuel_scoop = CASE WHEN purchase_item->>'item' = 'fuel_scoop' 
          THEN true ELSE device_fuel_scoop END,
        device_last_seen = CASE WHEN purchase_item->>'item' = 'last_seen_device' 
          THEN true ELSE device_last_seen END
      WHERE player_id = p_player_id;
    END IF;
  END LOOP;
  
  -- Get remaining credits
  SELECT credits INTO remaining_credits
  FROM ships
  WHERE player_id = p_player_id;
  
  RETURN json_build_object(
    'success', true,
    'total_cost', total_cost,
    'remaining_credits', remaining_credits
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.game_trade(uuid, uuid, text, text, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_trade(uuid, uuid, text, text, integer, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.purchase_special_port_items(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.purchase_special_port_items(uuid, jsonb) TO service_role;
