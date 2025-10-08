-- Migration: 327_improved_ai_system.sql
-- Purpose: Create a robust, intelligent AI system that doesn't get stuck

-- 1. Create improved AI decision function with proper error handling
CREATE OR REPLACE FUNCTION public.ai_make_decision(p_player_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_player_id uuid;
  v_player_handle text;
  v_sector_id uuid;
  v_turns int;
  v_is_ai boolean;
  v_credits bigint;
  v_hull_level int;
  v_hull_max int;
  v_armor_lvl int;
  v_energy int;
  v_fighters int;
  v_torpedoes int;
  v_planets_count int := 0;
  v_commodity_ports_count int := 0;
  v_special_ports_count int := 0;
  v_warps_count int := 0;
  v_decision text;
  v_decision_weight int;
BEGIN
  -- Get comprehensive player and ship info
  SELECT p.id, p.handle, p.current_sector, p.turns, p.is_ai,
         s.credits, s.hull, s.hull_max, s.armor_lvl, s.energy, s.fighters, s.torpedoes
  INTO v_player_id, v_player_handle, v_sector_id, v_turns, v_is_ai, v_credits, v_hull_level, v_hull_max, v_armor_lvl, v_energy, v_fighters, v_torpedoes
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.is_ai = true;
  
  IF NOT FOUND THEN
    RETURN 'wait';
  END IF;
  
  v_turns := COALESCE(v_turns, 0);
  
  -- Get comprehensive sector information
  SELECT 
    (SELECT COUNT(*) FROM public.planets pl 
     WHERE pl.sector_id = v_sector_id AND pl.owner_player_id IS NULL) as unclaimed_planets,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind IN ('ore', 'organics', 'goods', 'energy')) as commodity_ports,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind = 'special') as special_ports,
    (SELECT COUNT(*) FROM public.warps w 
     WHERE w.from_sector_id = v_sector_id) as warps_count
  INTO v_planets_count, v_commodity_ports_count, v_special_ports_count, v_warps_count;
  
  -- Decision logic with weighted priorities
  v_decision := 'wait'; -- Default fallback
  
  -- Priority 1: No turns = wait
  IF v_turns <= 0 THEN
    v_decision := 'wait';
    
  -- Priority 2: Claim planets (high value, limited opportunity)
  ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
    
  -- Priority 3: Trade at commodity ports (immediate profit)
  ELSIF v_commodity_ports_count > 0 AND v_credits >= 100 THEN
    v_decision := 'trade';
    
  -- Priority 4: Upgrade ship at special ports (long-term benefit)
  ELSIF v_special_ports_count > 0 AND v_credits >= 500 AND v_hull_level < 5 THEN
    v_decision := 'upgrade_ship';
    
  -- Priority 5: Explore (only if we have warps to explore)
  ELSIF v_warps_count > 0 THEN
    v_decision := 'explore';
    
  -- Priority 6: Emergency actions
  ELSIF v_credits < 100 THEN
    v_decision := 'emergency_trade';
    
  ELSE
    -- Fallback: wait for better opportunities
    v_decision := 'wait';
  END IF;
  
  RETURN v_decision;
EXCEPTION WHEN OTHERS THEN
  -- Log error and return safe fallback
  RETURN 'wait';
END;
$$;

-- 2. Drop existing function first to avoid parameter name conflicts
DROP FUNCTION IF EXISTS public.ai_execute_action(uuid, uuid, text);

-- 3. Create robust AI action execution function
CREATE OR REPLACE FUNCTION public.ai_execute_action(
  p_player_id uuid,
  p_universe_id uuid,
  p_action text
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_result boolean := false;
  v_user_id uuid;
  v_sector_id uuid;
  v_sector_number int;
  v_port_id uuid;
  v_port_kind text;
  v_planet_id uuid;
  v_available_warps int[];
  v_target_sector int;
  v_action_result jsonb;
BEGIN
  -- Get player info with error handling
  SELECT user_id, current_sector 
  INTO v_user_id, v_sector_id
  FROM public.players 
  WHERE id = p_player_id AND is_ai = true;
  
  IF v_user_id IS NULL OR v_sector_id IS NULL THEN
    RETURN false;
  END IF;
  
  -- Get current sector number
  SELECT number INTO v_sector_number
  FROM public.sectors
  WHERE id = v_sector_id;
  
  IF v_sector_number IS NULL THEN
    RETURN false;
  END IF;
  
  -- Execute action based on decision
  CASE p_action
    WHEN 'claim_planet' THEN
      -- Find first unclaimed planet in current sector
      SELECT id INTO v_planet_id
      FROM public.planets
      WHERE sector_id = v_sector_id 
        AND owner_player_id IS NULL
      LIMIT 1;
      
      IF v_planet_id IS NOT NULL THEN
        BEGIN
          SELECT public.game_planet_claim(v_user_id, v_sector_number, 'AI Colony', p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    WHEN 'trade' THEN
      -- Find commodity port (not special port)
      SELECT id, kind 
      INTO v_port_id, v_port_kind
      FROM public.ports
      WHERE sector_id = v_sector_id 
        AND kind IN ('ore', 'organics', 'goods', 'energy')
      LIMIT 1;
      
      IF v_port_id IS NOT NULL THEN
        BEGIN
          -- Try to buy ore (simple trade)
          SELECT public.game_trade(v_user_id, v_port_id, 'buy', 'ore', 1, p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    WHEN 'upgrade_ship' THEN
      -- Find special port
      SELECT id 
      INTO v_port_id
      FROM public.ports
      WHERE sector_id = v_sector_id 
        AND kind = 'special'
      LIMIT 1;
      
      IF v_port_id IS NOT NULL THEN
        BEGIN
          -- Try to upgrade hull
          SELECT public.game_ship_upgrade(v_user_id, 'hull', p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    WHEN 'explore' THEN
      -- Get available warps from current sector
      SELECT ARRAY_AGG(s.number)
      INTO v_available_warps
      FROM public.warps w
      JOIN public.sectors s ON s.id = w.to_sector_id
      WHERE w.from_sector_id = v_sector_id;
      
      IF v_available_warps IS NOT NULL AND array_length(v_available_warps, 1) > 0 THEN
        -- Pick random connected sector
        v_target_sector := v_available_warps[1 + floor(random() * array_length(v_available_warps, 1))::int];
        
        BEGIN
          SELECT public.game_move(v_user_id, v_target_sector, p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    WHEN 'emergency_trade' THEN
      -- Try to sell any cargo for credits
      SELECT id 
      INTO v_port_id
      FROM public.ports
      WHERE sector_id = v_sector_id 
        AND kind IN ('ore', 'organics', 'goods', 'energy')
      LIMIT 1;
      
      IF v_port_id IS NOT NULL THEN
        BEGIN
          -- Try to sell ore
          SELECT public.game_trade(v_user_id, v_port_id, 'sell', 'ore', 1, p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    ELSE
      v_result := false;
  END CASE;
  
  RETURN v_result;
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;

-- 4. Create improved AI runner with better error handling and statistics
CREATE OR REPLACE FUNCTION public.run_ai_player_actions(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_player record;
  v_decision text;
  v_result boolean;
  v_actions_taken int := 0;
  v_players_processed int := 0;
  v_trades int := 0;
  v_upgrades int := 0;
  v_planets_claimed int := 0;
  v_explorations int := 0;
  v_waits int := 0;
  v_errors int := 0;
  v_total_ai int := 0;
  v_ai_with_turns int := 0;
BEGIN
  -- Count AI players
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  -- Process each AI player
  FOR v_player IN 
    SELECT 
      p.id as player_id,
      p.user_id,
      p.handle,
      p.turns,
      s.credits,
      s.hull
    FROM public.players p
    JOIN public.ships s ON s.player_id = p.id
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = true
      AND COALESCE(p.turns, 0) > 0
    ORDER BY p.turns DESC, s.credits DESC -- Process AI with most resources first
  LOOP
    v_players_processed := v_players_processed + 1;
    
    BEGIN
      -- Make decision
      v_decision := ai_make_decision(v_player.player_id);
      
      -- Execute action
      v_result := ai_execute_action(v_player.player_id, p_universe_id, v_decision);
      
      IF v_result THEN
        v_actions_taken := v_actions_taken + 1;
        
        -- Track action types
        CASE v_decision
          WHEN 'trade', 'emergency_trade' THEN 
            v_trades := v_trades + 1;
          WHEN 'upgrade_ship' THEN 
            v_upgrades := v_upgrades + 1;
          WHEN 'claim_planet' THEN 
            v_planets_claimed := v_planets_claimed + 1;
          WHEN 'explore' THEN 
            v_explorations := v_explorations + 1;
          WHEN 'wait' THEN 
            v_waits := v_waits + 1;
        END CASE;
      ELSE
        v_errors := v_errors + 1;
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;
  
  -- Return comprehensive results
  RETURN jsonb_build_object(
    'success', true,
    'message', 'AI actions completed',
    'players_processed', v_players_processed,
    'actions_taken', v_actions_taken,
    'trades', v_trades,
    'upgrades', v_upgrades,
    'planets_claimed', v_planets_claimed,
    'explorations', v_explorations,
    'waits', v_waits,
    'errors', v_errors,
    'total_ai_players', v_total_ai,
    'ai_with_turns', v_ai_with_turns,
    'success_rate', CASE WHEN v_players_processed > 0 THEN 
      ROUND((v_actions_taken::numeric / v_players_processed::numeric) * 100, 2) 
    ELSE 0 END
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Failed to run AI player actions: ' || SQLERRM,
    'players_processed', v_players_processed,
    'actions_taken', v_actions_taken
  );
END;
$$;

-- 5. Create AI memory update function for learning
CREATE OR REPLACE FUNCTION public.update_ai_memory(
  p_player_id uuid,
  p_action text,
  p_success boolean,
  p_message text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Update or insert AI memory
  INSERT INTO public.ai_player_memory (
    player_id, 
    current_goal, 
    last_action, 
    action_count,
    efficiency_score,
    updated_at
  ) VALUES (
    p_player_id,
    p_action,
    p_action,
    1,
    CASE WHEN p_success THEN 1.0 ELSE 0.0 END,
    NOW()
  )
  ON CONFLICT (player_id) 
  DO UPDATE SET
    current_goal = CASE WHEN p_success THEN p_action ELSE current_goal END,
    last_action = p_action,
    action_count = ai_player_memory.action_count + 1,
    efficiency_score = (ai_player_memory.efficiency_score * 0.9) + (CASE WHEN p_success THEN 0.1 ELSE 0.0 END),
    updated_at = NOW();
EXCEPTION WHEN OTHERS THEN
  -- Silently ignore memory update errors
  NULL;
END;
$$;

-- 6. Create AI health check function
CREATE OR REPLACE FUNCTION public.check_ai_health(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_total_ai int;
  v_active_ai int;
  v_stuck_ai int;
  v_low_credits_ai int;
  v_no_turns_ai int;
  v_avg_efficiency numeric;
BEGIN
  -- Count AI players by status
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  SELECT COUNT(*) INTO v_active_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  SELECT COUNT(*) INTO v_no_turns_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) <= 0;
  
  SELECT COUNT(*) INTO v_low_credits_ai
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND s.credits < 100;
  
  -- Calculate average efficiency
  SELECT COALESCE(AVG(m.efficiency_score), 0) INTO v_avg_efficiency
  FROM public.ai_player_memory m
  JOIN public.players p ON p.id = m.player_id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  RETURN jsonb_build_object(
    'total_ai_players', v_total_ai,
    'active_ai_players', v_active_ai,
    'ai_without_turns', v_no_turns_ai,
    'ai_low_credits', v_low_credits_ai,
    'average_efficiency', ROUND(v_avg_efficiency, 3),
    'health_status', CASE 
      WHEN v_active_ai = 0 THEN 'critical'
      WHEN v_active_ai < v_total_ai * 0.5 THEN 'poor'
      WHEN v_avg_efficiency < 0.3 THEN 'fair'
      ELSE 'good'
    END
  );
END;
$$;
