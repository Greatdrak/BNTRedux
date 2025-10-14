-- Enhanced Player Logging
-- Add logging to movement functions and other actions that should be logged

-- Enhanced game_move function with logging
CREATE OR REPLACE FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer, "p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_player_id uuid;
  v_current_sector_id uuid;
  v_target_sector_id uuid;
  v_current_sector_number integer;
  v_turns integer;
  v_exists boolean;
BEGIN
  -- Get player in universe
  SELECT id, current_sector, turns
    INTO v_player_id, v_current_sector_id, v_turns
  FROM public.players
  WHERE user_id = p_user_id AND universe_id = p_universe_id
  LIMIT 1;

  IF v_player_id IS NULL THEN
    RETURN jsonb_build_object('error', 'player_not_found');
  END IF;

  -- Get current sector number
  SELECT number INTO v_current_sector_number
  FROM public.sectors
  WHERE id = v_current_sector_id;

  -- Validate target sector exists in same universe
  SELECT id INTO v_target_sector_id
  FROM public.sectors
  WHERE universe_id = p_universe_id AND number = p_to_sector_number
  LIMIT 1;

  IF v_target_sector_id IS NULL THEN
    RETURN jsonb_build_object('error', 'target_sector_not_found');
  END IF;

  -- Check warp connectivity using sector UUIDs
  SELECT EXISTS (
    SELECT 1 FROM public.warps
    WHERE universe_id = p_universe_id
      AND from_sector = v_current_sector_id
      AND to_sector = v_target_sector_id
  ) INTO v_exists;

  IF NOT v_exists THEN
    RETURN jsonb_build_object('error', 'no_warp_connection');
  END IF;

  -- Ensure at least 1 turn
  IF COALESCE(v_turns, 0) < 1 THEN
    RETURN jsonb_build_object('error', 'insufficient_turns');
  END IF;

  -- Perform move: decrement turns and set sector
  UPDATE public.players
  SET current_sector = v_target_sector_id,
      turns = v_turns - 1
  WHERE id = v_player_id;

  -- Mandatory turn tracking
  PERFORM public.track_turn_spent(v_player_id);

  -- Log the movement
  BEGIN
    INSERT INTO public.player_logs (player_id, kind, ref_id, message, occurred_at)
    VALUES (
      v_player_id, 
      'warp_move', 
      v_target_sector_id, 
      'You moved from sector ' || v_current_sector_number || ' to sector ' || p_to_sector_number || ' via warp.',
      NOW()
    );
  EXCEPTION WHEN OTHERS THEN
    -- Ignore logging errors
    NULL;
  END;

  -- Return success with new sector number
  RETURN jsonb_build_object(
    'ok', true,
    'to', p_to_sector_number
  );
END;
$$;

-- Enhanced game_hyperspace function with logging
CREATE OR REPLACE FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id UUID;
  v_turns INT;
  v_current_sector_id UUID;
  v_current_number INT;
  v_target_sector_id UUID;
  v_engine_lvl INT;
  v_cost INT;
BEGIN
  -- Load player, current sector, ship - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT p.id, p.turns, p.current_sector
    INTO v_player_id, v_turns, v_current_sector_id
    FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
  ELSE
    SELECT p.id, p.turns, p.current_sector
    INTO v_player_id, v_turns, v_current_sector_id
    FROM players p WHERE p.user_id = p_user_id;
  END IF;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  SELECT s.number INTO v_current_number FROM sectors s WHERE s.id = v_current_sector_id;

  -- Get target sector - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT id INTO v_target_sector_id 
    FROM sectors 
    WHERE number = p_target_sector_number AND universe_id = p_universe_id;
  ELSE
    SELECT id INTO v_target_sector_id 
    FROM sectors 
    WHERE number = p_target_sector_number;
  END IF;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Target sector not found'));
  END IF;

  -- Get engine level
  SELECT engine_lvl INTO v_engine_lvl FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  -- Calculate cost
  -- At engine level 15+, cost is 1 turn for any distance; scales based on distance at lower levels
  IF v_engine_lvl >= 15 THEN
    v_cost := 1;
  ELSE
    v_cost := GREATEST(1, CEIL(ABS(p_target_sector_number - v_current_number) / GREATEST(1, v_engine_lvl)));
  END IF;

  -- Check turns
  IF v_turns < v_cost THEN
    RETURN json_build_object('error', json_build_object('code','insufficient_turns','message','Not enough turns'));
  END IF;

  -- Perform jump
  UPDATE players SET 
    current_sector = v_target_sector_id,
    turns = turns - v_cost
  WHERE id = v_player_id;

  -- Log the hyperspace jump
  BEGIN
    INSERT INTO public.player_logs (player_id, kind, ref_id, message, occurred_at)
    VALUES (
      v_player_id, 
      'hyperspace_jump', 
      v_target_sector_id, 
      'You jumped from sector ' || v_current_number || ' to sector ' || p_target_sector_number || ' via hyperspace (cost: ' || v_cost || ' turns).',
      NOW()
    );
  EXCEPTION WHEN OTHERS THEN
    -- Ignore logging errors
    NULL;
  END;

  -- Return success
  RETURN json_build_object(
    'ok', true,
    'message', 'Hyperspace jump successful',
    'cost', v_cost,
    'player', json_build_object(
      'id', v_player_id,
      'turns', v_turns - v_cost,
      'current_sector', v_target_sector_id,
      'current_sector_number', p_target_sector_number
    )
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', json_build_object('code','server_error','message','Hyperspace operation failed: ' || SQLERRM));
END;
$$;

-- Enhanced game_trade function with logging
CREATE OR REPLACE FUNCTION "public"."game_trade"("p_user_id" "uuid", "p_port_id" "uuid", "p_action" "text", "p_resource" "text", "p_qty" integer, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id UUID;
  v_ship RECORD;
  v_port RECORD;
  v_unit_price NUMERIC;
  v_total NUMERIC;
  v_cargo_used INTEGER;
  v_cargo_free INTEGER;
  v_energy_free INTEGER;
  v_result JSON;
BEGIN
  -- Get player and ship info
  IF p_universe_id IS NOT NULL THEN
    SELECT p.id INTO v_player_id FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
  ELSE
    SELECT p.id INTO v_player_id FROM players p WHERE p.user_id = p_user_id;
  END IF;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  SELECT * INTO v_ship FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  -- Get port info
  SELECT * INTO v_port FROM ports WHERE id = p_port_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Port not found'));
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

    -- UPDATED: Check capacity based on resource type
    IF p_resource = 'energy' THEN
      -- Energy uses separate capacity (energy_max)
      v_energy_free := v_ship.energy_max - v_ship.energy;
      IF p_qty > v_energy_free THEN
        RETURN json_build_object('error', json_build_object(
          'code','insufficient_energy_capacity',
          'message','Insufficient energy capacity (available: ' || v_energy_free || '). Upgrade Power at a Special Port.'
        ));
      END IF;
    ELSE
      -- Other resources use cargo capacity
      v_cargo_used := v_ship.ore + v_ship.organics + v_ship.goods;
      v_cargo_free := v_ship.cargo - v_cargo_used;
      IF p_qty > v_cargo_free THEN
        RETURN json_build_object('error', json_build_object('code','insufficient_cargo','message','Insufficient cargo space'));
      END IF;
    END IF;

    -- Check if port has enough stock
    CASE p_resource
      WHEN 'ore' THEN
        IF v_port.stock_ore < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient stock'));
        END IF;
      WHEN 'organics' THEN
        IF v_port.stock_organics < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient stock'));
        END IF;
      WHEN 'goods' THEN
        IF v_port.stock_goods < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient stock'));
        END IF;
      WHEN 'energy' THEN
        IF v_port.stock_energy < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient stock'));
        END IF;
    END CASE;

    -- Execute buy transaction
    UPDATE ships SET credits = credits - v_total WHERE player_id = v_player_id;
    
    CASE p_resource
      WHEN 'ore' THEN
        UPDATE ships SET ore = ore + p_qty WHERE player_id = v_player_id;
        UPDATE ports SET stock_ore = stock_ore - p_qty WHERE id = p_port_id;
      WHEN 'organics' THEN
        UPDATE ships SET organics = organics + p_qty WHERE player_id = v_player_id;
        UPDATE ports SET stock_organics = stock_organics - p_qty WHERE id = p_port_id;
      WHEN 'goods' THEN
        UPDATE ships SET goods = goods + p_qty WHERE player_id = v_player_id;
        UPDATE ports SET stock_goods = stock_goods - p_qty WHERE id = p_port_id;
      WHEN 'energy' THEN
        UPDATE ships SET energy = energy + p_qty WHERE player_id = v_player_id;
        UPDATE ports SET stock_energy = stock_energy - p_qty WHERE id = p_port_id;
    END CASE;

    -- Log the trade (only for manual trades, not trade routes)
    -- Trade routes use game_trade_auto which doesn't call this function
    BEGIN
      INSERT INTO public.player_logs (player_id, kind, ref_id, message, occurred_at)
      VALUES (
        v_player_id, 
        'trade_buy', 
        p_port_id, 
        'You bought ' || p_qty || ' ' || p_resource || ' for ' || v_total || ' credits at a ' || v_port.kind || ' port.',
        NOW()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Ignore logging errors
      NULL;
    END;

    RETURN json_build_object(
      'ok', true,
      'action', 'buy',
      'resource', p_resource,
      'quantity', p_qty,
      'total_cost', v_total,
      'credits_remaining', v_ship.credits - v_total
    );

  -- Handle sell action
  ELSIF p_action = 'sell' THEN
    -- Check if player has enough of the resource
    CASE p_resource
      WHEN 'ore' THEN
        IF v_ship.ore < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_resource','message','Not enough ore'));
        END IF;
      WHEN 'organics' THEN
        IF v_ship.organics < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_resource','message','Not enough organics'));
        END IF;
      WHEN 'goods' THEN
        IF v_ship.goods < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_resource','message','Not enough goods'));
        END IF;
    END CASE;

    -- Execute sell transaction
    UPDATE ships SET credits = credits + v_total WHERE player_id = v_player_id;
    
    CASE p_resource
      WHEN 'ore' THEN
        UPDATE ships SET ore = ore - p_qty WHERE player_id = v_player_id;
        UPDATE ports SET stock_ore = stock_ore + p_qty WHERE id = p_port_id;
      WHEN 'organics' THEN
        UPDATE ships SET organics = organics - p_qty WHERE player_id = v_player_id;
        UPDATE ports SET stock_organics = stock_organics + p_qty WHERE id = p_port_id;
      WHEN 'goods' THEN
        UPDATE ships SET goods = goods - p_qty WHERE player_id = v_player_id;
        UPDATE ports SET stock_goods = stock_goods + p_qty WHERE id = p_port_id;
    END CASE;

    -- Log the trade (only for manual trades, not trade routes)
    -- Trade routes use game_trade_auto which doesn't call this function
    BEGIN
      INSERT INTO public.player_logs (player_id, kind, ref_id, message, occurred_at)
      VALUES (
        v_player_id, 
        'trade_sell', 
        p_port_id, 
        'You sold ' || p_qty || ' ' || p_resource || ' for ' || v_total || ' credits at a ' || v_port.kind || ' port.',
        NOW()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Ignore logging errors
      NULL;
    END;

    RETURN json_build_object(
      'ok', true,
      'action', 'sell',
      'resource', p_resource,
      'quantity', p_qty,
      'total_earned', v_total,
      'credits_after', v_ship.credits + v_total
    );

  ELSE
    RETURN json_build_object('error', json_build_object('code','invalid_action','message','Invalid action'));
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', json_build_object('code','server_error','message','Trade operation failed: ' || SQLERRM));
END;
$$;

-- Enhanced execute_trade_route function with logging
-- This will log trade route completions (not individual trades)
CREATE OR REPLACE FUNCTION "public"."execute_trade_route"("p_user_id" "uuid", "p_route_id" "uuid", "p_max_iterations" integer DEFAULT 1, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_player RECORD;
    v_route RECORD;
    v_execution_id UUID;
    v_start_port RECORD;
    v_target_port RECORD;
    v_trade_result JSONB;
    v_move_result JSON;
    v_log TEXT := '';
    v_turns_spent INTEGER := 0;
    v_total_profit BIGINT := 0;
    v_turns_before INTEGER;
    v_turns_after INTEGER;
    v_credits_before NUMERIC;
    v_credits_after NUMERIC;
    v_movement_type TEXT;
    v_distance INTEGER;
    v_engine_level INTEGER;
BEGIN
    -- Get player info with ship engine level (filter by universe if provided)
    IF p_universe_id IS NOT NULL THEN
        SELECT p.*, s.engine_lvl
        INTO v_player
        FROM players p
        JOIN ships s ON p.id = s.player_id
        WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
    ELSE
        SELECT p.*, s.engine_lvl
        INTO v_player
        FROM players p
        JOIN ships s ON p.id = s.player_id
        WHERE p.user_id = p_user_id;
    END IF;

    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
    END IF;

    v_player_id := v_player.id;
    v_turns_before := v_player.turns;

    -- Credits are on ships now
    SELECT credits INTO v_credits_before FROM ships WHERE player_id = v_player_id;

    v_engine_level := v_player.engine_lvl;

    -- Get route info including movement_type
    SELECT tr.* INTO v_route
    FROM trade_routes tr
    WHERE tr.id = p_route_id AND tr.player_id = v_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'route_not_found', 'message', 'Route not found'));
    END IF;

    -- Get waypoints (should be 2: start and target)
    SELECT rw.*, p.id as port_id, p.kind as port_kind, p.sector_id, s.number as sector_number
    INTO v_start_port
    FROM route_waypoints rw
    JOIN ports p ON rw.port_id = p.id
    JOIN sectors s ON p.sector_id = s.id
    WHERE rw.route_id = p_route_id
    ORDER BY rw.sequence_order
    LIMIT 1;

    SELECT rw.*, p.id as port_id, p.kind as port_kind, p.sector_id, s.number as sector_number
    INTO v_target_port
    FROM route_waypoints rw
    JOIN ports p ON rw.port_id = p.id
    JOIN sectors s ON p.sector_id = s.id
    WHERE rw.route_id = p_route_id
    ORDER BY rw.sequence_order
    OFFSET 1
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'no_waypoints', 'message', 'Route needs 2 waypoints'));
    END IF;

    -- Get movement type from route (default to warp if not set)
    v_movement_type := COALESCE(v_route.movement_type, 'warp');
    v_distance := ABS(v_target_port.sector_number - v_start_port.sector_number);

    v_log := 'Starting trade route execution' || E'\n';
    v_log := v_log || 'Start port: Sector ' || v_start_port.sector_number || ' (' || v_start_port.port_kind || ')' || E'\n';
    v_log := v_log || 'Target port: Sector ' || v_target_port.sector_number || ' (' || v_target_port.port_kind || ')' || E'\n';
    v_log := v_log || 'Movement type: ' || v_movement_type || E'\n';
    v_log := v_log || 'Initial state - Turns: ' || v_turns_before || ', Credits: ' || v_credits_before || E'\n';

    -- Calculate required turns based on movement type (include start trade if applicable)
    DECLARE
        v_required_turns INTEGER;
    BEGIN
        IF v_movement_type = 'warp' THEN
            v_required_turns := 3; -- 1 move to target + 1 trade at target + 1 move back
        ELSE -- realspace
            v_required_turns := (v_distance * 2) + 1; -- distance turns each way + 1 trade at target
        END IF;
        -- If the player starts at the start port and we will trade there, add 1 more turn
        IF v_player.current_sector = v_start_port.sector_id THEN
            v_required_turns := v_required_turns + 1;
        END IF;

        IF v_player.turns < v_required_turns THEN
            RETURN json_build_object('error', json_build_object('code', 'insufficient_turns', 'message', 'Need at least ' || v_required_turns || ' turns'));
        END IF;
    END;

    -- Create execution record
    INSERT INTO route_executions (route_id, player_id, status, started_at)
    VALUES (p_route_id, v_player_id, 'running', now())
    RETURNING id INTO v_execution_id;

    -- STEP 1: Trade at start port (if player is there)
    IF v_player.current_sector = v_start_port.sector_id THEN
        v_log := v_log || 'Trading at start port...' || E'\n';

        SELECT game_trade_auto(p_user_id, v_start_port.port_id, p_universe_id) INTO v_trade_result;

        v_log := v_log || 'Start trade result: ' || v_trade_result::text || E'\n';

        IF (v_trade_result->>'ok')::boolean = true THEN
            v_turns_spent := v_turns_spent + 1;
            -- Deduct 1 turn for the successful trade at start port
            UPDATE players SET turns = GREATEST(0, turns - 1) WHERE id = v_player_id;
            v_log := v_log || 'Start port trade successful (1 turn spent)' || E'\n';
        ELSE
            v_log := v_log || 'Start port trade failed: ' || (v_trade_result->>'message') || E'\n';
        END IF;
    ELSE
        v_log := v_log || 'Not at start port, skipping start trade' || E'\n';
    END IF;

    -- STEP 2: Move to target port using correct movement function
    v_log := v_log || 'Moving to target port using ' || v_movement_type || '...' || E'\n';

    IF v_movement_type = 'warp' THEN
        SELECT game_move(p_user_id, v_target_port.sector_number, p_universe_id) INTO v_move_result;
    ELSE -- realspace
        SELECT game_hyperspace(p_user_id, v_target_port.sector_number, p_universe_id) INTO v_move_result;
    END IF;

    v_log := v_log || 'Move result: ' || v_move_result::text || E'\n';

    -- Check if move failed (either ok=false or error field exists)
    IF (v_move_result->>'ok')::boolean = false OR (v_move_result::jsonb) ? 'error' THEN
        v_log := v_log || 'Move failed: ' || COALESCE(v_move_result->>'message', v_move_result->>'error', 'Unknown error');
        UPDATE route_executions SET status = 'failed', error_message = v_log, completed_at = now() WHERE id = v_execution_id;
        RETURN json_build_object('error', json_build_object('code', 'move_failed', 'message', v_log));
    END IF;

    v_turns_spent := v_turns_spent + 1;
    -- Deduct 1 turn for the successful move to target
    UPDATE players SET turns = GREATEST(0, turns - 1) WHERE id = v_player_id;
    v_log := v_log || 'Moved to target port (1 turn spent)' || E'\n';

    -- STEP 3: Trade at target port
    v_log := v_log || 'Trading at target port...' || E'\n';

    SELECT game_trade_auto(p_user_id, v_target_port.port_id, p_universe_id) INTO v_trade_result;

    v_log := v_log || 'Target trade result: ' || v_trade_result::text || E'\n';

    -- Check if trade failed (either ok=false or error field exists)
    IF (v_trade_result->>'ok')::boolean = false OR (v_trade_result::jsonb) ? 'error' THEN
        v_log := v_log || 'Target port trade failed: ' || COALESCE(v_trade_result->>'message', v_trade_result->'error'->>'message', 'Unknown error');
        UPDATE route_executions SET status = 'failed', error_message = v_log, completed_at = now() WHERE id = v_execution_id;
        RETURN json_build_object('error', json_build_object('code', 'trade_failed', 'message', v_log));
    END IF;

    v_turns_spent := v_turns_spent + 1;
    -- Deduct 1 turn for the successful trade at target port
    UPDATE players SET turns = GREATEST(0, turns - 1) WHERE id = v_player_id;
    v_log := v_log || 'Target port trade successful (1 turn spent)' || E'\n';

    -- STEP 4: Move back to start port using correct movement function
    v_log := v_log || 'Moving back to start port using ' || v_movement_type || '...' || E'\n';

    IF v_movement_type = 'warp' THEN
        SELECT game_move(p_user_id, v_start_port.sector_number, p_universe_id) INTO v_move_result;
    ELSE -- realspace
        SELECT game_hyperspace(p_user_id, v_start_port.sector_number, p_universe_id) INTO v_move_result;
    END IF;

    v_log := v_log || 'Return move result: ' || v_move_result::text || E'\n';

    -- Check if return move failed (either ok=false or error field exists)
    IF (v_move_result->>'ok')::boolean = false OR (v_move_result::jsonb) ? 'error' THEN
        v_log := v_log || 'Return move failed: ' || COALESCE(v_move_result->>'message', v_move_result->>'error', 'Unknown error');
        UPDATE route_executions SET status = 'failed', error_message = v_log, completed_at = now() WHERE id = v_execution_id;
        RETURN json_build_object('error', json_build_object('code', 'return_move_failed', 'message', v_log));
    END IF;

    v_turns_spent := v_turns_spent + 1;
    -- Deduct 1 turn for the successful return move
    UPDATE players SET turns = GREATEST(0, turns - 1) WHERE id = v_player_id;
    v_log := v_log || 'Returned to start port (1 turn spent)' || E'\n';

    -- Calculate final profit
    SELECT credits INTO v_credits_after FROM ships WHERE player_id = v_player_id;
    v_total_profit := v_credits_after - v_credits_before;

    -- Update execution record as completed
    UPDATE route_executions 
    SET status = 'completed', 
        completed_at = now(),
        turns_spent = v_turns_spent,
        profit = v_total_profit
    WHERE id = v_execution_id;

    v_log := v_log || 'Trade route completed successfully!' || E'\n';
    v_log := v_log || 'Total turns spent: ' || v_turns_spent || E'\n';
    v_log := v_log || 'Total profit: ' || v_total_profit || ' credits' || E'\n';

    -- Log the trade route completion
    BEGIN
        INSERT INTO public.player_logs (player_id, kind, ref_id, message, occurred_at)
        VALUES (
            v_player_id, 
            'trade_route_completed', 
            p_route_id, 
            'Trade route completed: ' || v_start_port.port_kind || ' port (sector ' || v_start_port.sector_number || 
            ') to ' || v_target_port.port_kind || ' port (sector ' || v_target_port.sector_number || 
            ') via ' || v_movement_type || '. Profit: ' || v_total_profit || ' credits, Turns spent: ' || v_turns_spent,
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        -- Ignore logging errors
        NULL;
    END;

    RETURN json_build_object(
        'ok', true,
        'message', 'Trade route executed successfully',
        'turns_spent', v_turns_spent,
        'total_profit', v_total_profit,
        'log', v_log
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Update execution record as failed
        UPDATE route_executions 
        SET status = 'failed', 
            completed_at = now(),
            error_message = 'Unexpected error: ' || SQLERRM
        WHERE id = v_execution_id;
        
        RETURN json_build_object('error', json_build_object('code', 'server_error', 'message', 'Trade route execution failed: ' || SQLERRM));
END;
$$;
