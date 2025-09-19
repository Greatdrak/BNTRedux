-- Update remaining RPC functions to use ship credits instead of player credits
-- This migration updates all functions that still reference p.credits from players table

-- Update game_engine_upgrade function
DROP FUNCTION IF EXISTS public.game_engine_upgrade(uuid);

CREATE OR REPLACE FUNCTION public.game_engine_upgrade(
  p_user_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID;
  v_ship_credits BIGINT;
  v_engine_lvl INT;
  v_cost INT;
BEGIN
  -- Get player and ship data
  SELECT p.id, s.credits INTO v_player_id, v_ship_credits 
  FROM players p 
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  SELECT engine_lvl INTO v_engine_lvl FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  v_cost := 500 * (v_engine_lvl + 1);
  IF v_ship_credits < v_cost THEN
    RETURN json_build_object('error', json_build_object('code','insufficient_funds','message','Insufficient credits'));
  END IF;

  -- Update ship credits and engine level
  UPDATE ships SET 
    credits = credits - v_cost,
    engine_lvl = engine_lvl + 1 
  WHERE player_id = v_player_id;

  -- Return success with updated values
  SELECT credits, engine_lvl INTO v_ship_credits, v_engine_lvl
  FROM ships
  WHERE player_id = v_player_id;

  RETURN json_build_object(
    'success', true,
    'credits', v_ship_credits,
    'engine_lvl', v_engine_lvl,
    'cost', v_cost
  );
END;
$$;

-- Update game_repair function
DROP FUNCTION IF EXISTS public.game_repair(uuid, integer);

CREATE OR REPLACE FUNCTION public.game_repair(
  p_user_id uuid,
  p_hull integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID;
  v_ship_credits BIGINT;
  v_current_sector UUID;
  v_port_id UUID;
  v_ship_id UUID;
  v_current_hull INTEGER;
  v_hull_max INTEGER := 100;
  v_hull_repair_cost INTEGER := 2;
  v_actual_repair INTEGER;
  v_total_cost INTEGER;
  v_result JSON;
BEGIN
  IF p_hull <= 0 THEN
    RETURN json_build_object('error', 'Repair amount must be positive');
  END IF;
  
  -- Get player and ship data
  SELECT p.id, s.credits, p.current_sector, s.id
  INTO v_player_id, v_ship_credits, v_current_sector, v_ship_id
  FROM players p 
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Player not found');
  END IF;

  -- Check if player is at a port
  SELECT id INTO v_port_id FROM ports WHERE sector_id = v_current_sector;
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Must be at a port to repair');
  END IF;

  -- Get current hull
  SELECT hull INTO v_current_hull FROM ships WHERE id = v_ship_id;
  
  -- Calculate actual repair needed
  v_actual_repair := LEAST(p_hull, v_hull_max - v_current_hull);
  v_total_cost := v_actual_repair * v_hull_repair_cost;
  
  -- Check if player has enough credits
  IF v_ship_credits < v_total_cost THEN
    RETURN json_build_object('error', 'Insufficient credits');
  END IF;
  
  -- Perform repair
  UPDATE ships SET 
    hull = hull + v_actual_repair,
    credits = credits - v_total_cost
  WHERE id = v_ship_id;
  
  -- Return success
  RETURN json_build_object(
    'success', true,
    'repaired', v_actual_repair,
    'cost', v_total_cost,
    'new_hull', v_current_hull + v_actual_repair
  );
END;
$$;

-- Update game_upgrade function (for fighters/torpedoes)
DROP FUNCTION IF EXISTS public.game_upgrade(uuid, text, integer);

CREATE OR REPLACE FUNCTION public.game_upgrade(
  p_user_id uuid,
  p_item text,
  p_qty integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID;
  v_ship_credits BIGINT;
  v_current_sector UUID;
  v_port_id UUID;
  v_ship_id UUID;
  v_fighters INTEGER;
  v_torpedoes INTEGER;
  v_unit_cost INTEGER;
  v_total_cost INTEGER;
  v_result JSON;
BEGIN
  -- Validate item type
  IF p_item NOT IN ('fighters', 'torpedoes') THEN
    RETURN json_build_object('error', 'Invalid item type');
  END IF;
  
  IF p_qty <= 0 THEN
    RETURN json_build_object('error', 'Quantity must be positive');
  END IF;
  
  -- Get player and ship data
  SELECT p.id, s.credits, p.current_sector, s.id
  INTO v_player_id, v_ship_credits, v_current_sector, v_ship_id
  FROM players p 
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Player not found');
  END IF;

  -- Ensure there is a port in the player's current sector
  SELECT id INTO v_port_id FROM ports WHERE sector_id = v_current_sector;
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Must be at a port to upgrade');
  END IF;

  -- Get current ship stats
  SELECT fighters, torpedoes INTO v_fighters, v_torpedoes FROM ships WHERE id = v_ship_id;
  
  -- Set unit cost based on item type
  IF p_item = 'fighters' THEN
    v_unit_cost := 50;
  ELSIF p_item = 'torpedoes' THEN
    v_unit_cost := 120;
  END IF;
  
  v_total_cost := p_qty * v_unit_cost;
  
  -- Check if player has enough credits
  IF v_ship_credits < v_total_cost THEN
    RETURN json_build_object('error', 'Insufficient credits');
  END IF;
  
  -- Perform upgrade
  IF p_item = 'fighters' THEN
    UPDATE ships SET 
      fighters = fighters + p_qty,
      credits = credits - v_total_cost
    WHERE id = v_ship_id;
  ELSIF p_item = 'torpedoes' THEN
    UPDATE ships SET 
      torpedoes = torpedoes + p_qty,
      credits = credits - v_total_cost
    WHERE id = v_ship_id;
  END IF;
  
  -- Return success
  RETURN json_build_object(
    'success', true,
    'item', p_item,
    'quantity', p_qty,
    'cost', v_total_cost,
    'new_fighters', CASE WHEN p_item = 'fighters' THEN v_fighters + p_qty ELSE v_fighters END,
    'new_torpedoes', CASE WHEN p_item = 'torpedoes' THEN v_torpedoes + p_qty ELSE v_torpedoes END
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.game_engine_upgrade(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_engine_upgrade(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.game_repair(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_repair(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.game_upgrade(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_upgrade(uuid, text, integer) TO service_role;
