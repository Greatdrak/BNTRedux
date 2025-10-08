-- Enhanced AI System with Comprehensive Logging
-- This will help us debug exactly what's happening with AI players

-- 1. Create a logging function for AI debugging
CREATE OR REPLACE FUNCTION public.log_ai_debug(
  p_player_id uuid,
  p_universe_id uuid,
  p_step text,
  p_data jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Log to a temporary table for debugging
  INSERT INTO public.ai_action_log (
    player_id,
    universe_id,
    action_type,
    action_data,
    success,
    message,
    created_at
  ) VALUES (
    p_player_id,
    p_universe_id,
    p_step,
    p_data,
    true,
    'Debug: ' || p_step,
    NOW()
  );
EXCEPTION WHEN OTHERS THEN
  -- Ignore logging errors
  NULL;
END;
$$;

-- 2. Enhanced AI decision function with detailed logging
CREATE OR REPLACE FUNCTION public.ai_make_decision_debug(p_player_id uuid, p_universe_id uuid)
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
  v_debug_data jsonb;
BEGIN
  -- Log start of decision process
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_start', 
    jsonb_build_object('player_id', p_player_id));
  
  -- Get comprehensive player and ship info
  SELECT p.id, p.handle, p.current_sector, p.turns, p.is_ai,
         s.credits, s.hull, s.hull_max, s.armor_lvl, s.energy, s.fighters, s.torpedoes
  INTO v_player_id, v_player_handle, v_sector_id, v_turns, v_is_ai, v_credits, v_hull_level, v_hull_max, v_armor_lvl, v_energy, v_fighters, v_torpedoes
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.is_ai = true;
  
  IF NOT FOUND THEN
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'player_not_found', 
      jsonb_build_object('player_id', p_player_id));
    RETURN 'wait';
  END IF;
  
  v_turns := COALESCE(v_turns, 0);
  
  -- Log player data
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'player_data', 
    jsonb_build_object(
      'handle', v_player_handle,
      'turns', v_turns,
      'credits', v_credits,
      'hull', v_hull_level,
      'sector_id', v_sector_id
    ));
  
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
  
  -- Log sector data
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'sector_data', 
    jsonb_build_object(
      'planets_count', v_planets_count,
      'commodity_ports_count', v_commodity_ports_count,
      'special_ports_count', v_special_ports_count,
      'warps_count', v_warps_count
    ));
  
  -- Decision logic with weighted priorities
  v_decision := 'wait'; -- Default fallback
  
  -- Priority 1: No turns = wait
  IF v_turns <= 0 THEN
    v_decision := 'wait';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_no_turns', 
      jsonb_build_object('turns', v_turns));
    
  -- Priority 2: Claim planets (high value, limited opportunity)
  ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_claim_planet', 
      jsonb_build_object('planets_count', v_planets_count, 'credits', v_credits));
    
  -- Priority 3: Trade at commodity ports (immediate profit)
  ELSIF v_commodity_ports_count > 0 AND v_credits >= 100 THEN
    v_decision := 'trade';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_trade', 
      jsonb_build_object('commodity_ports_count', v_commodity_ports_count, 'credits', v_credits));
    
  -- Priority 4: Upgrade ship at special ports (long-term benefit)
  ELSIF v_special_ports_count > 0 AND v_credits >= 500 AND v_hull_level < 5 THEN
    v_decision := 'upgrade_ship';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_upgrade', 
      jsonb_build_object('special_ports_count', v_special_ports_count, 'credits', v_credits, 'hull', v_hull_level));
    
  -- Priority 5: Explore (only if we have warps to explore)
  ELSIF v_warps_count > 0 THEN
    v_decision := 'explore';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_explore', 
      jsonb_build_object('warps_count', v_warps_count));
    
  -- Priority 6: Emergency actions
  ELSIF v_credits < 100 THEN
    v_decision := 'emergency_trade';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_emergency', 
      jsonb_build_object('credits', v_credits));
    
  ELSE
    -- Fallback: wait for better opportunities
    v_decision := 'wait';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_wait_fallback', 
      jsonb_build_object('reason', 'no_suitable_actions'));
  END IF;
  
  -- Log final decision
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_final', 
    jsonb_build_object('decision', v_decision));
  
  RETURN v_decision;
EXCEPTION WHEN OTHERS THEN
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_error', 
    jsonb_build_object('error', SQLERRM));
  RETURN 'wait';
END;
$$;

-- 3. Enhanced AI runner with comprehensive logging
CREATE OR REPLACE FUNCTION public.run_ai_player_actions_debug(p_universe_id uuid)
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
  v_debug_info jsonb;
BEGIN
  -- Log start of AI processing
  PERFORM log_ai_debug(NULL, p_universe_id, 'ai_processing_start', 
    jsonb_build_object('universe_id', p_universe_id));
  
  -- Count AI players
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  -- Log counts
  PERFORM log_ai_debug(NULL, p_universe_id, 'ai_counts', 
    jsonb_build_object('total_ai', v_total_ai, 'ai_with_turns', v_ai_with_turns));
  
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
    
    -- Log player being processed
    PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'processing_player', 
      jsonb_build_object(
        'handle', v_player.handle,
        'turns', v_player.turns,
        'credits', v_player.credits,
        'hull', v_player.hull
      ));
    
    BEGIN
      -- Make decision
      v_decision := ai_make_decision_debug(v_player.player_id, p_universe_id);
      
      -- Log decision
      PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'decision_made', 
        jsonb_build_object('decision', v_decision));
      
      -- Execute action
      v_result := ai_execute_action(v_player.player_id, p_universe_id, v_decision);
      
      -- Log execution result
      PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'action_executed', 
        jsonb_build_object('decision', v_decision, 'success', v_result));
      
      IF v_result THEN
        v_actions_taken := v_actions_taken + 1;
        
        -- Track action type for stats
        CASE v_decision
          WHEN 'trade' THEN v_trades := v_trades + 1;
          WHEN 'upgrade_ship' THEN v_upgrades := v_upgrades + 1;
          WHEN 'claim_planet' THEN v_planets_claimed := v_planets_claimed + 1;
          WHEN 'explore' THEN v_explorations := v_explorations + 1;
          WHEN 'wait' THEN v_waits := v_waits + 1;
          ELSE NULL;
        END CASE;
      ELSE
        v_errors := v_errors + 1;
        PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'action_failed', 
          jsonb_build_object('decision', v_decision));
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'player_error', 
        jsonb_build_object('error', SQLERRM));
    END;
  END LOOP;
  
  -- Log final results
  PERFORM log_ai_debug(NULL, p_universe_id, 'ai_processing_complete', 
    jsonb_build_object(
      'players_processed', v_players_processed,
      'actions_taken', v_actions_taken,
      'trades', v_trades,
      'upgrades', v_upgrades,
      'planets_claimed', v_planets_claimed,
      'explorations', v_explorations,
      'waits', v_waits,
      'errors', v_errors
    ));
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'ok',
    'ai_total', v_total_ai,
    'ai_with_turns', v_ai_with_turns,
    'ai_with_goal', v_total_ai, -- All AI have goals
    'players_processed', v_players_processed,
    'actions_taken', v_actions_taken,
    'trades', v_trades,
    'upgrades', v_upgrades,
    'planets_claimed', v_planets_claimed,
    'explorations', v_explorations,
    'waits', v_waits,
    'errors', v_errors
  );
EXCEPTION WHEN OTHERS THEN
  PERFORM log_ai_debug(NULL, p_universe_id, 'ai_processing_error', 
    jsonb_build_object('error', SQLERRM));
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Failed to run AI player actions: ' || SQLERRM
  );
END;
$$;
