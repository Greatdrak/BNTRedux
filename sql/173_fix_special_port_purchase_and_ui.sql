-- Fix special port purchase issues and add missing tech upgrades
-- This addresses the armor constraint violation and adds missing tech upgrades

-- First, add the missing armor_lvl column to ships table and clean up armor columns
ALTER TABLE ships ADD COLUMN IF NOT EXISTS armor_lvl INTEGER DEFAULT 1;

-- Add armor column back - armor points are purchasable items like fighters/torpedoes
-- armor_lvl determines capacity, armor stores current armor points
ALTER TABLE ships ADD COLUMN IF NOT EXISTS armor INTEGER DEFAULT 0;

-- Fix the armor constraint to allow proper armor values
-- Drop the existing constraint if it exists
ALTER TABLE ships DROP CONSTRAINT IF EXISTS ships_armor_range;

-- Add a new constraint that allows armor from 0 to a reasonable maximum
ALTER TABLE ships ADD CONSTRAINT ships_armor_range CHECK (armor >= 0 AND armor <= 1000000);

-- First, let's check what the armor constraint is and fix it
-- The error shows armor constraint violation, so let's ensure armor values are valid

-- Update the purchase function to handle armor constraints properly
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
  v_ship RECORD;
BEGIN
  -- Get current ship data
  SELECT * INTO v_ship
  FROM ships
  WHERE player_id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Ship not found');
  END IF;
  
  -- Calculate total cost
  FOR purchase_item IN SELECT * FROM jsonb_array_elements(p_purchases)
  LOOP
    item_cost := (purchase_item->>'quantity')::integer * (purchase_item->>'cost')::integer;
    total_cost := total_cost + item_cost;
  END LOOP;
  
  -- Check if player has enough credits
  IF v_ship.credits < total_cost THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient credits');
  END IF;
  
  -- Process each purchase
  FOR purchase_item IN SELECT * FROM jsonb_array_elements(p_purchases)
  LOOP
    item_cost := (purchase_item->>'quantity')::integer * (purchase_item->>'cost')::integer;
    
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
        device_space_beacons = CASE WHEN purchase_item->>'name' = 'Space Beacons' 
          THEN device_space_beacons + (purchase_item->>'quantity')::integer 
          ELSE device_space_beacons END,
        device_warp_editors = CASE WHEN purchase_item->>'name' = 'Warp Editors' 
          THEN device_warp_editors + (purchase_item->>'quantity')::integer 
          ELSE device_warp_editors END,
        device_genesis_torpedoes = CASE WHEN purchase_item->>'name' = 'Genesis Torpedoes' 
          THEN device_genesis_torpedoes + (purchase_item->>'quantity')::integer 
          ELSE device_genesis_torpedoes END,
        device_mine_deflectors = CASE WHEN purchase_item->>'name' = 'Mine Deflectors' 
          THEN device_mine_deflectors + (purchase_item->>'quantity')::integer 
          ELSE device_mine_deflectors END,
        device_emergency_warp = CASE WHEN purchase_item->>'name' = 'Emergency Warp Device' 
          THEN true ELSE device_emergency_warp END,
        device_escape_pod = CASE WHEN purchase_item->>'name' = 'Escape Pod' 
          THEN true ELSE device_escape_pod END,
        device_fuel_scoop = CASE WHEN purchase_item->>'name' = 'Fuel Scoop' 
          THEN true ELSE device_fuel_scoop END,
        device_last_seen = CASE WHEN purchase_item->>'name' = 'Last Ship Seen Device' 
          THEN true ELSE device_last_seen END
      WHERE player_id = p_player_id;
    ELSIF purchase_item->>'type' = 'item' THEN
      -- Handle item purchases with proper constraint validation
      UPDATE ships 
      SET 
        credits = credits - item_cost,
        colonists = CASE WHEN purchase_item->>'name' = 'Colonists' 
          THEN LEAST(colonists + (purchase_item->>'quantity')::integer, 100 * POWER(1.5, hull_lvl)) -- Cap at BNT hull capacity
          ELSE colonists END,
        fighters = CASE WHEN purchase_item->>'name' = 'Fighters' 
          THEN fighters + (purchase_item->>'quantity')::integer 
          ELSE fighters END,
        torpedoes = CASE WHEN purchase_item->>'name' = 'Torpedoes' 
          THEN torpedoes + (purchase_item->>'quantity')::integer 
          ELSE torpedoes END,
        armor = CASE WHEN purchase_item->>'name' = 'Armor Points' 
          THEN LEAST(COALESCE(armor, 0) + (purchase_item->>'quantity')::integer, 100 * POWER(1.5, armor_lvl)) -- Cap at armor capacity
          ELSE COALESCE(armor, 0) END
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

-- Add missing tech upgrades to the game_ship_upgrade function
DROP FUNCTION IF EXISTS public.game_ship_upgrade(uuid, text, uuid);

CREATE OR REPLACE FUNCTION public.game_ship_upgrade(
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
    v_ship_credits BIGINT;
BEGIN
    -- Get player info
    IF p_universe_id IS NOT NULL THEN
        SELECT * INTO v_player FROM players WHERE user_id = p_user_id AND universe_id = p_universe_id;
    ELSE
        SELECT * INTO v_player FROM players WHERE user_id = p_user_id;
    END IF;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
    END IF;

    -- Get ship info
    SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'ship_not_found', 'message', 'Ship not found'));
    END IF;

    -- Check if player is at a Special port
    IF NOT EXISTS (
        SELECT 1 FROM ports p 
        JOIN sectors s ON p.sector_id = s.id 
        WHERE s.id = v_player.current_sector AND p.kind = 'special'
    ) THEN
        RETURN json_build_object('error', json_build_object('code', 'wrong_port', 'message', 'Must be at a Special port to upgrade'));
    END IF;

    -- Calculate cost based on attribute and current level (BNT doubling formula: 1000 * 2^(level-1))
    CASE p_attr
        WHEN 'engine' THEN v_cost := 1000 * POWER(2, v_ship.engine_lvl);
        WHEN 'computer' THEN v_cost := 1000 * POWER(2, v_ship.comp_lvl);
        WHEN 'sensors' THEN v_cost := 1000 * POWER(2, v_ship.sensor_lvl);
        WHEN 'shields' THEN v_cost := 1000 * POWER(2, v_ship.shield_lvl);
        WHEN 'hull' THEN v_cost := 1000 * POWER(2, v_ship.hull_lvl);
        WHEN 'power' THEN v_cost := 1000 * POWER(2, v_ship.power_lvl);
        WHEN 'beam' THEN v_cost := 1000 * POWER(2, v_ship.beam_lvl);
        WHEN 'torp_launcher' THEN v_cost := 1000 * POWER(2, v_ship.torp_launcher_lvl);
        WHEN 'armor' THEN v_cost := 1000 * POWER(2, v_ship.armor_lvl);
        ELSE
            RETURN json_build_object('error', json_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
    END CASE;

    -- Check if ship has enough credits (use ship credits, not player credits)
    IF v_ship.credits < v_cost THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
    END IF;

    -- Apply upgrade and deduct credits from ship
    CASE p_attr
        WHEN 'engine' THEN 
            UPDATE ships SET engine_lvl = engine_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'computer' THEN 
            UPDATE ships SET comp_lvl = comp_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'sensors' THEN 
            UPDATE ships SET sensor_lvl = sensor_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'shields' THEN 
            UPDATE ships SET shield_lvl = shield_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'hull' THEN 
            UPDATE ships SET hull_lvl = hull_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'power' THEN 
            UPDATE ships SET power_lvl = power_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'beam' THEN 
            UPDATE ships SET beam_lvl = beam_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'torp_launcher' THEN 
            UPDATE ships SET torp_launcher_lvl = torp_launcher_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'armor' THEN 
            UPDATE ships SET armor_lvl = armor_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
    END CASE;

    -- Get updated ship data
    SELECT * INTO v_ship FROM ships WHERE id = v_ship.id;
    SELECT credits INTO v_ship_credits FROM ships WHERE id = v_ship.id;

    -- Return success with updated data
    RETURN json_build_object(
        'success', true,
        'credits', v_ship_credits,
        'cost', v_cost,
        'attribute', p_attr,
        'new_level', CASE p_attr
            WHEN 'engine' THEN v_ship.engine_lvl
            WHEN 'computer' THEN v_ship.comp_lvl
            WHEN 'sensors' THEN v_ship.sensor_lvl
            WHEN 'shields' THEN v_ship.shield_lvl
            WHEN 'hull' THEN v_ship.hull_lvl
            WHEN 'power' THEN v_ship.power_lvl
            WHEN 'beam' THEN v_ship.beam_lvl
            WHEN 'torp_launcher' THEN v_ship.torp_launcher_lvl
        END
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.game_ship_upgrade(uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_ship_upgrade(uuid, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.purchase_special_port_items(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.purchase_special_port_items(uuid, jsonb) TO service_role;
