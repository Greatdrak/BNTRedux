-- Fix execute_trade_route to use ship credits instead of player credits
-- Drops old versions and recreates the universe-aware version

-- Drop existing versions to avoid signature conflicts
DROP FUNCTION IF EXISTS public.execute_trade_route(UUID, UUID, INTEGER);
DROP FUNCTION IF EXISTS public.execute_trade_route(UUID, UUID, INTEGER, UUID);

-- Recreate execute_trade_route with p_universe_id and ship credits handling
CREATE OR REPLACE FUNCTION public.execute_trade_route(
    p_user_id UUID,
    p_route_id UUID,
    p_max_iterations INTEGER DEFAULT 1,
    p_universe_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
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
        RETURN json_build_object('error', json_build_object('code', 'return_failed', 'message', v_log));
    END IF;

    v_turns_spent := v_turns_spent + 1;
    -- Deduct 1 turn for the successful return move
    UPDATE players SET turns = GREATEST(0, turns - 1) WHERE id = v_player_id;
    v_log := v_log || 'Returned to start port (1 turn spent)' || E'\n';

    -- Get final player turns and ship credits
    SELECT turns INTO v_turns_after FROM players WHERE id = v_player_id;
    SELECT credits INTO v_credits_after FROM ships WHERE player_id = v_player_id;

    v_log := v_log || 'Final state - Turns: ' || v_turns_after || ' (was ' || v_turns_before || '), Credits: ' || v_credits_after || ' (was ' || v_credits_before || ')' || E'\n';
    v_log := v_log || 'Trade route completed! Total turns: ' || v_turns_spent || E'\n';

    -- Update execution record
    UPDATE route_executions 
    SET 
        status = 'completed',
        total_profit = v_total_profit,
        turns_spent = v_turns_spent,
        completed_at = now(),
        execution_data = json_build_object('log', v_log)
    WHERE id = v_execution_id;

    -- Increment player's cumulative turns_spent for leaderboard/analytics (best-effort)
    BEGIN
        PERFORM public.track_turn_spent(v_player_id, v_turns_spent, 'execute_trade_route');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'track_turn_spent not available or failed: %', SQLERRM;
    END;

    -- Update route
    UPDATE trade_routes 
    SET last_executed_at = now(), updated_at = now()
    WHERE id = p_route_id;

    RETURN json_build_object(
        'ok', true,
        'execution_id', v_execution_id,
        'total_profit', v_total_profit,
        'turns_spent', v_turns_spent,
        'log', v_log,
        'message', 'Trade route completed successfully'
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', json_build_object('code','internal_error','message','Internal server error: ' || SQLERRM));
END;
$$;


