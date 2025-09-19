-- Ship Capacity Calculation Functions
-- RPC functions to calculate ship capacity based on ship levels

-- Function to calculate ship capacity for different items
CREATE OR REPLACE FUNCTION calculate_ship_capacity(
  p_ship_id UUID,
  p_capacity_type TEXT
) RETURNS INTEGER AS $$
DECLARE
  ship_record RECORD;
  capacity INTEGER := 0;
BEGIN
  -- Get ship data
  SELECT * INTO ship_record FROM ships WHERE id = p_ship_id;
  
  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  
  -- Calculate capacity based on type
  CASE p_capacity_type
    WHEN 'fighters' THEN
      -- Fighters limited by computer level (comp_lvl)
      -- Formula: comp_lvl * 10 (standard BNT formula)
      capacity := ship_record.comp_lvl * 10;
      
    WHEN 'torpedoes' THEN
      -- Torpedoes limited by torpedo launcher level (torp_launcher_lvl)
      -- Formula: torp_launcher_lvl * 10 (standard BNT formula)
      capacity := ship_record.torp_launcher_lvl * 10;
      
    WHEN 'armor' THEN
      -- Armor limited by armor level (calculated from armor_max)
      -- Formula: armor_max (already calculated based on armor level)
      capacity := ship_record.armor_max;
      
    WHEN 'colonists' THEN
      -- Colonists limited by cargo space (hull level)
      -- Same as commodity cargo space
      capacity := ship_record.cargo;
      
    WHEN 'energy' THEN
      -- Energy limited by power level (power_lvl)
      -- Formula: power_lvl * 100 (standard BNT formula)
      capacity := ship_record.power_lvl * 100;
      
    ELSE
      capacity := 0;
  END CASE;
  
  RETURN GREATEST(capacity, 0);
END;
$$ LANGUAGE plpgsql;

-- Function to get comprehensive ship capacity data
CREATE OR REPLACE FUNCTION get_ship_capacity_data(
  p_ship_id UUID
) RETURNS JSONB AS $$
DECLARE
  ship_record RECORD;
  capacity_data JSONB;
BEGIN
  -- Get ship data
  SELECT * INTO ship_record FROM ships WHERE id = p_ship_id;
  
  IF NOT FOUND THEN
    RETURN '{}'::JSONB;
  END IF;
  
  -- Build capacity data object
  capacity_data := jsonb_build_object(
    'fighters', jsonb_build_object(
      'current', ship_record.fighters,
      'max', ship_record.comp_lvl * 10,
      'level', ship_record.comp_lvl
    ),
    'torpedoes', jsonb_build_object(
      'current', ship_record.torpedoes,
      'max', ship_record.torp_launcher_lvl * 10,
      'level', ship_record.torp_launcher_lvl
    ),
    'armor', jsonb_build_object(
      'current', ship_record.armor,
      'max', ship_record.armor_max,
      'level', CASE 
        WHEN ship_record.armor_max = 0 THEN 0
        ELSE FLOOR(ship_record.armor_max / 100.0)
      END
    ),
    'colonists', jsonb_build_object(
      'current', ship_record.colonists,
      'max', ship_record.cargo,
      'level', ship_record.hull_lvl
    ),
    'energy', jsonb_build_object(
      'current', ship_record.energy,
      'max', ship_record.power_lvl * 100,
      'level', ship_record.power_lvl
    ),
    'devices', jsonb_build_object(
      'space_beacons', jsonb_build_object(
        'current', ship_record.device_space_beacons,
        'max', -1, -- Unlimited
        'cost', 100000
      ),
      'warp_editors', jsonb_build_object(
        'current', ship_record.device_warp_editors,
        'max', -1, -- Unlimited
        'cost', 1000000
      ),
      'genesis_torpedoes', jsonb_build_object(
        'current', ship_record.device_genesis_torpedoes,
        'max', -1, -- Unlimited
        'cost', 10000000
      ),
      'mine_deflectors', jsonb_build_object(
        'current', ship_record.device_mine_deflectors,
        'max', -1, -- Unlimited
        'cost', 1000
      ),
      'emergency_warp', jsonb_build_object(
        'current', ship_record.device_emergency_warp,
        'max', 1,
        'cost', 5000000
      ),
      'escape_pod', jsonb_build_object(
        'current', ship_record.device_escape_pod,
        'max', 1,
        'cost', 1000000
      ),
      'fuel_scoop', jsonb_build_object(
        'current', ship_record.device_fuel_scoop,
        'max', 1,
        'cost', 100000
      ),
      'last_seen', jsonb_build_object(
        'current', ship_record.device_last_seen,
        'max', 1,
        'cost', 10000000
      )
    )
  );
  
  RETURN capacity_data;
END;
$$ LANGUAGE plpgsql;

-- Function to purchase items at special port
CREATE OR REPLACE FUNCTION purchase_special_port_items(
  p_player_id UUID,
  p_purchases JSONB
) RETURNS JSONB AS $$
DECLARE
  ship_record RECORD;
  player_record RECORD;
  purchase_item JSONB;
  item_type TEXT;
  item_name TEXT;
  quantity INTEGER;
  cost INTEGER;
  total_cost INTEGER := 0;
  success BOOLEAN := true;
  error_message TEXT := '';
  result JSONB;
BEGIN
  -- Get player and ship data
  SELECT * INTO player_record FROM players WHERE id = p_player_id;
  SELECT * INTO ship_record FROM ships WHERE player_id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Player or ship not found');
  END IF;
  
  -- Validate and calculate total cost
  FOR purchase_item IN SELECT * FROM jsonb_array_elements(p_purchases)
  LOOP
    item_type := purchase_item->>'type';
    item_name := purchase_item->>'name';
    quantity := (purchase_item->>'quantity')::INTEGER;
    cost := (purchase_item->>'cost')::INTEGER;
    
    -- Validate quantity
    IF quantity <= 0 THEN
      CONTINUE;
    END IF;
    
    -- Add to total cost
    total_cost := total_cost + (quantity * cost);
  END LOOP;
  
  -- Check if player has enough credits
  IF player_record.credits < total_cost THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'Insufficient credits',
      'required', total_cost,
      'available', player_record.credits
    );
  END IF;
  
  -- Process purchases
  FOR purchase_item IN SELECT * FROM jsonb_array_elements(p_purchases)
  LOOP
    item_type := purchase_item->>'type';
    item_name := purchase_item->>'name';
    quantity := (purchase_item->>'quantity')::INTEGER;
    
    IF quantity <= 0 THEN
      CONTINUE;
    END IF;
    
    -- Process based on item type
    CASE item_type
      WHEN 'fighters' THEN
        UPDATE ships SET fighters = LEAST(fighters + quantity, comp_lvl * 10) WHERE player_id = p_player_id;
      WHEN 'torpedoes' THEN
        UPDATE ships SET torpedoes = LEAST(torpedoes + quantity, torp_launcher_lvl * 10) WHERE player_id = p_player_id;
      WHEN 'armor' THEN
        UPDATE ships SET armor = LEAST(armor + quantity, armor_max) WHERE player_id = p_player_id;
      WHEN 'colonists' THEN
        UPDATE ships SET colonists = LEAST(colonists + quantity, cargo) WHERE player_id = p_player_id;
      WHEN 'energy' THEN
        UPDATE ships SET energy = LEAST(energy + quantity, power_lvl * 100) WHERE player_id = p_player_id;
      WHEN 'device' THEN
        CASE item_name
          WHEN 'Space Beacons' THEN
            UPDATE ships SET device_space_beacons = device_space_beacons + quantity WHERE player_id = p_player_id;
          WHEN 'Warp Editors' THEN
            UPDATE ships SET device_warp_editors = device_warp_editors + quantity WHERE player_id = p_player_id;
          WHEN 'Genesis Torpedoes' THEN
            UPDATE ships SET device_genesis_torpedoes = device_genesis_torpedoes + quantity WHERE player_id = p_player_id;
          WHEN 'Mine Deflectors' THEN
            UPDATE ships SET device_mine_deflectors = device_mine_deflectors + quantity WHERE player_id = p_player_id;
          WHEN 'Emergency Warp' THEN
            UPDATE ships SET device_emergency_warp = true WHERE player_id = p_player_id;
          WHEN 'Escape Pod' THEN
            UPDATE ships SET device_escape_pod = true WHERE player_id = p_player_id;
          WHEN 'Fuel Scoop' THEN
            UPDATE ships SET device_fuel_scoop = true WHERE player_id = p_player_id;
          WHEN 'Last Ship Seen Device' THEN
            UPDATE ships SET device_last_seen = true WHERE player_id = p_player_id;
        END CASE;
    END CASE;
  END LOOP;
  
  -- Deduct credits
  UPDATE players SET credits = credits - total_cost WHERE id = p_player_id;
  
  -- Return success
  RETURN jsonb_build_object(
    'success', true,
    'total_cost', total_cost,
    'remaining_credits', player_record.credits - total_cost
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql;
