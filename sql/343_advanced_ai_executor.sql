-- Advanced AI Action Executor with Multi-Turn Support
-- This executes the strategic decisions with multiple turns per action

CREATE OR REPLACE FUNCTION public.ai_execute_strategic_action(
  p_player_id uuid, 
  p_universe_id uuid, 
  p_action_data jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_action text;
  v_turns_to_spend int;
  v_reason text;
  v_priority int;
  v_user_id uuid;
  v_sector_id uuid;
  v_sector_number int;
  v_result jsonb;
  v_actions_executed int := 0;
  v_turns_used int := 0;
  v_success boolean := false;
  v_port_id uuid;
  v_planet_id uuid;
  v_target_sector int;
  v_warps int[];
  v_trade_result jsonb;
  v_move_result jsonb;
  v_claim_result jsonb;
  v_upgrade_result jsonb;
BEGIN
  -- Extract action data
  v_action := p_action_data->>'action';
  v_turns_to_spend := COALESCE((p_action_data->>'turns_to_spend')::int, 1);
  v_reason := p_action_data->>'reason';
  v_priority := COALESCE((p_action_data->>'priority')::int, 50);
  
  -- Get player info
  SELECT user_id, current_sector 
  INTO v_user_id, v_sector_id
  FROM public.players 
  WHERE id = p_player_id AND is_ai = true;
  
  IF v_user_id IS NULL OR v_sector_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'player_not_found');
  END IF;
  
  -- Get current sector number
  SELECT number INTO v_sector_number
  FROM public.sectors
  WHERE id = v_sector_id;
  
  -- Execute action based on type
  CASE v_action
    WHEN 'trade_route' THEN
      -- Execute multiple trades to build cargo
      FOR i IN 1..LEAST(v_turns_to_spend, 20) LOOP
        BEGIN
          -- Find a commodity port
          SELECT id INTO v_port_id
          FROM public.ports
          WHERE sector_id = v_sector_id 
            AND kind IN ('ore', 'organics', 'goods', 'energy')
          LIMIT 1;
          
          IF v_port_id IS NOT NULL THEN
            -- Execute trade (buy ore)
            SELECT public.game_trade(v_user_id, v_port_id, 'buy', 'ore', 1, p_universe_id) INTO v_trade_result;
            
            IF (v_trade_result->>'success')::boolean THEN
              v_actions_executed := v_actions_executed + 1;
              v_turns_used := v_turns_used + 1;
            END IF;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          -- Continue on error
          NULL;
        END;
      END LOOP;
      v_success := v_actions_executed > 0;
      
    WHEN 'explore_deep' THEN
      -- Execute multiple moves to explore deeply
      FOR i IN 1..LEAST(v_turns_to_spend, 30) LOOP
        BEGIN
          -- Get available warps
          SELECT ARRAY_AGG(w.to_sector_number) INTO v_warps
          FROM public.warps w
          WHERE w.from_sector_id = v_sector_id;
          
          IF v_warps IS NOT NULL AND array_length(v_warps, 1) > 0 THEN
            -- Pick random warp
            v_target_sector := v_warps[floor(random() * array_length(v_warps, 1)) + 1];
            
            -- Execute move
            SELECT public.game_move(v_user_id, v_target_sector, p_universe_id) INTO v_move_result;
            
            IF (v_move_result->>'success')::boolean THEN
              v_actions_executed := v_actions_executed + 1;
              v_turns_used := v_turns_used + 1;
              
              -- Update sector for next iteration
              SELECT id INTO v_sector_id
              FROM public.sectors
              WHERE number = v_target_sector AND universe_id = p_universe_id;
            END IF;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          -- Continue on error
          NULL;
        END;
      END LOOP;
      v_success := v_actions_executed > 0;
      
    WHEN 'explore_sell' THEN
      -- Explore while looking for places to sell cargo
      FOR i IN 1..LEAST(v_turns_to_spend, 15) LOOP
        BEGIN
          -- Get available warps
          SELECT ARRAY_AGG(w.to_sector_number) INTO v_warps
          FROM public.warps w
          WHERE w.from_sector_id = v_sector_id;
          
          IF v_warps IS NOT NULL AND array_length(v_warps, 1) > 0 THEN
            -- Pick random warp
            v_target_sector := v_warps[floor(random() * array_length(v_warps, 1)) + 1];
            
            -- Execute move
            SELECT public.game_move(v_user_id, v_target_sector, p_universe_id) INTO v_move_result;
            
            IF (v_move_result->>'success')::boolean THEN
              v_actions_executed := v_actions_executed + 1;
              v_turns_used := v_turns_used + 1;
              
              -- Update sector for next iteration
              SELECT id INTO v_sector_id
              FROM public.sectors
              WHERE number = v_target_sector AND universe_id = p_universe_id;
            END IF;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          -- Continue on error
          NULL;
        END;
      END LOOP;
      v_success := v_actions_executed > 0;
      
    WHEN 'patrol' THEN
      -- Patrol owned territory
      FOR i IN 1..LEAST(v_turns_to_spend, 20) LOOP
        BEGIN
          -- Get available warps
          SELECT ARRAY_AGG(w.to_sector_number) INTO v_warps
          FROM public.warps w
          WHERE w.from_sector_id = v_sector_id;
          
          IF v_warps IS NOT NULL AND array_length(v_warps, 1) > 0 THEN
            -- Pick random warp
            v_target_sector := v_warps[floor(random() * array_length(v_warps, 1)) + 1];
            
            -- Execute move
            SELECT public.game_move(v_user_id, v_target_sector, p_universe_id) INTO v_move_result;
            
            IF (v_move_result->>'success')::boolean THEN
              v_actions_executed := v_actions_executed + 1;
              v_turns_used := v_turns_used + 1;
              
              -- Update sector for next iteration
              SELECT id INTO v_sector_id
              FROM public.sectors
              WHERE number = v_target_sector AND universe_id = p_universe_id;
            END IF;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          -- Continue on error
          NULL;
        END;
      END LOOP;
      v_success := v_actions_executed > 0;
      
    WHEN 'claim_planet' THEN
      -- Claim a planet
      BEGIN
        SELECT id INTO v_planet_id
        FROM public.planets
        WHERE sector_id = v_sector_id 
          AND owner_player_id IS NULL
        LIMIT 1;
        
        IF v_planet_id IS NOT NULL THEN
          SELECT public.game_planet_claim(v_user_id, v_sector_number, 'AI Colony', p_universe_id) INTO v_claim_result;
          
          IF (v_claim_result->>'success')::boolean THEN
            v_actions_executed := 1;
            v_turns_used := 1;
            v_success := true;
          END IF;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_success := false;
      END;
      
    WHEN 'upgrade_ship' THEN
      -- Upgrade ship
      BEGIN
        SELECT id INTO v_port_id
        FROM public.ports
        WHERE sector_id = v_sector_id AND kind = 'special'
        LIMIT 1;
        
        IF v_port_id IS NOT NULL THEN
          SELECT public.game_ship_upgrade(v_user_id, v_port_id, 'hull', p_universe_id) INTO v_upgrade_result;
          
          IF (v_upgrade_result->>'success')::boolean THEN
            v_actions_executed := 1;
            v_turns_used := 1;
            v_success := true;
          END IF;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_success := false;
      END;
      
    WHEN 'develop_planets' THEN
      -- Develop owned planets (simplified - just move around)
      FOR i IN 1..LEAST(v_turns_to_spend, 15) LOOP
        BEGIN
          -- Get available warps
          SELECT ARRAY_AGG(w.to_sector_number) INTO v_warps
          FROM public.warps w
          WHERE w.from_sector_id = v_sector_id;
          
          IF v_warps IS NOT NULL AND array_length(v_warps, 1) > 0 THEN
            -- Pick random warp
            v_target_sector := v_warps[floor(random() * array_length(v_warps, 1)) + 1];
            
            -- Execute move
            SELECT public.game_move(v_user_id, v_target_sector, p_universe_id) INTO v_move_result;
            
            IF (v_move_result->>'success')::boolean THEN
              v_actions_executed := v_actions_executed + 1;
              v_turns_used := v_turns_used + 1;
              
              -- Update sector for next iteration
              SELECT id INTO v_sector_id
              FROM public.sectors
              WHERE number = v_target_sector AND universe_id = p_universe_id;
            END IF;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          -- Continue on error
          NULL;
        END;
      END LOOP;
      v_success := v_actions_executed > 0;
      
    WHEN 'emergency_trade' THEN
      -- Emergency trading to get credits
      FOR i IN 1..LEAST(v_turns_to_spend, 10) LOOP
        BEGIN
          -- Find a commodity port
          SELECT id INTO v_port_id
          FROM public.ports
          WHERE sector_id = v_sector_id 
            AND kind IN ('ore', 'organics', 'goods', 'energy')
          LIMIT 1;
          
          IF v_port_id IS NOT NULL THEN
            -- Execute trade (buy ore)
            SELECT public.game_trade(v_user_id, v_port_id, 'buy', 'ore', 1, p_universe_id) INTO v_trade_result;
            
            IF (v_trade_result->>'success')::boolean THEN
              v_actions_executed := v_actions_executed + 1;
              v_turns_used := v_turns_used + 1;
            END IF;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          -- Continue on error
          NULL;
        END;
      END LOOP;
      v_success := v_actions_executed > 0;
      
    WHEN 'explore' THEN
      -- Simple exploration
      FOR i IN 1..LEAST(v_turns_to_spend, 10) LOOP
        BEGIN
          -- Get available warps
          SELECT ARRAY_AGG(w.to_sector_number) INTO v_warps
          FROM public.warps w
          WHERE w.from_sector_id = v_sector_id;
          
          IF v_warps IS NOT NULL AND array_length(v_warps, 1) > 0 THEN
            -- Pick random warp
            v_target_sector := v_warps[floor(random() * array_length(v_warps, 1)) + 1];
            
            -- Execute move
            SELECT public.game_move(v_user_id, v_target_sector, p_universe_id) INTO v_move_result;
            
            IF (v_move_result->>'success')::boolean THEN
              v_actions_executed := v_actions_executed + 1;
              v_turns_used := v_turns_used + 1;
              
              -- Update sector for next iteration
              SELECT id INTO v_sector_id
              FROM public.sectors
              WHERE number = v_target_sector AND universe_id = p_universe_id;
            END IF;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          -- Continue on error
          NULL;
        END;
      END LOOP;
      v_success := v_actions_executed > 0;
      
    ELSE
      -- Default: wait
      v_success := true;
      v_actions_executed := 0;
      v_turns_used := 0;
  END CASE;
  
  RETURN jsonb_build_object(
    'success', v_success,
    'action', v_action,
    'actions_executed', v_actions_executed,
    'turns_used', v_turns_used,
    'reason', v_reason,
    'priority', v_priority
  );
END;
$$;
