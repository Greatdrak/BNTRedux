-- Advanced AI Runner with Strategic Planning and Multi-Turn Actions
-- This replaces the simple AI processor with sophisticated gameplay

CREATE OR REPLACE FUNCTION public.run_advanced_ai_actions(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_player record;
  v_decision jsonb;
  v_result jsonb;
  v_actions_taken int := 0;
  v_players_processed int := 0;
  v_trades int := 0;
  v_upgrades int := 0;
  v_planets_claimed int := 0;
  v_explorations int := 0;
  v_patrols int := 0;
  v_developments int := 0;
  v_emergency_trades int := 0;
  v_waits int := 0;
  v_errors int := 0;
  v_total_ai int := 0;
  v_ai_with_turns int := 0;
  v_total_turns_used int := 0;
BEGIN
  -- Count AI players
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  -- Process each AI player (limit to 5 for performance)
  FOR v_player IN 
    SELECT 
      p.id as player_id,
      p.user_id,
      p.handle,
      p.turns,
      s.credits,
      s.hull,
      s.ore,
      s.organics,
      s.goods,
      s.energy
    FROM public.players p
    JOIN public.ships s ON s.player_id = p.id
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = true
      AND COALESCE(p.turns, 0) > 0
    ORDER BY p.turns DESC, s.credits DESC
    LIMIT 5 -- Process 5 AI players per cycle
  LOOP
    v_players_processed := v_players_processed + 1;
    
    BEGIN
      -- Make strategic decision
      v_decision := ai_make_strategic_decision(v_player.player_id, p_universe_id);
      
      -- Execute strategic action
      v_result := ai_execute_strategic_action(v_player.player_id, p_universe_id, v_decision);
      
      -- Track results
      IF (v_result->>'success')::boolean THEN
        v_actions_taken := v_actions_taken + 1;
        v_total_turns_used := v_total_turns_used + COALESCE((v_result->>'turns_used')::int, 0);
        
        -- Track action types
        CASE v_result->>'action'
          WHEN 'trade_route' THEN v_trades := v_trades + 1;
          WHEN 'upgrade_ship' THEN v_upgrades := v_upgrades + 1;
          WHEN 'claim_planet' THEN v_planets_claimed := v_planets_claimed + 1;
          WHEN 'explore_deep', 'explore_sell', 'explore' THEN v_explorations := v_explorations + 1;
          WHEN 'patrol' THEN v_patrols := v_patrols + 1;
          WHEN 'develop_planets' THEN v_developments := v_developments + 1;
          WHEN 'emergency_trade' THEN v_emergency_trades := v_emergency_trades + 1;
          WHEN 'wait' THEN v_waits := v_waits + 1;
          ELSE NULL;
        END CASE;
      ELSE
        v_errors := v_errors + 1;
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Advanced AI processing completed',
    'ai_total', v_total_ai,
    'ai_with_turns', v_ai_with_turns,
    'ai_with_goal', v_total_ai,
    'players_processed', v_players_processed,
    'actions_taken', v_actions_taken,
    'total_turns_used', v_total_turns_used,
    'trades', v_trades,
    'upgrades', v_upgrades,
    'planets_claimed', v_planets_claimed,
    'explorations', v_explorations,
    'patrols', v_patrols,
    'developments', v_developments,
    'emergency_trades', v_emergency_trades,
    'waits', v_waits,
    'errors', v_errors
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'message', 'Failed to run advanced AI actions: ' || SQLERRM,
    'ai_total', 0,
    'ai_with_turns', 0,
    'ai_with_goal', 0,
    'players_processed', 0,
    'actions_taken', 0,
    'total_turns_used', 0,
    'trades', 0,
    'upgrades', 0,
    'planets_claimed', 0,
    'explorations', 0,
    'patrols', 0,
    'developments', 0,
    'emergency_trades', 0,
    'waits', 0,
    'errors', 1
  );
END;
$$;
