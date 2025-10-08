-- Migration: 302_instrument_ai_runner_logging.sql
-- Purpose: Add detailed logging to run_ai_player_actions for debugging

DROP FUNCTION IF EXISTS public.run_ai_player_actions(uuid);

CREATE OR REPLACE FUNCTION public.run_ai_player_actions(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_ai_player record;
  v_decision text;
  v_action_result boolean;
  v_actions_taken int := 0;
  v_players_processed int := 0;
  v_planets_claimed int := 0;
  v_upgrades int := 0;
  v_trades int := 0;
  v_result jsonb;
BEGIN
  -- Log start of AI run
  PERFORM log_ai_action(
    NULL, -- no specific player
    p_universe_id,
    'ai_run_start',
    'success',
    jsonb_build_object('universe_id', p_universe_id)
  );

  -- Process each AI player
  FOR v_ai_player IN 
    SELECT p.id, p.handle, p.current_sector, p.turns, p.is_ai,
           s.credits,
           m.current_goal, m.target_sector_id
    FROM public.players p
    JOIN public.ships s ON s.player_id = p.id
    LEFT JOIN public.ai_player_memory m ON m.player_id = p.id
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = true
      AND COALESCE(p.turns, 0) > 0
  LOOP
    v_players_processed := v_players_processed + 1;
    
    -- Log player processing start
    PERFORM log_ai_action(
      v_ai_player.id,
      p_universe_id,
      'player_process_start',
      'success',
      'Processing AI player: ' || v_ai_player.handle || ' in sector ' || v_ai_player.current_sector
    );

    -- Make decision
    BEGIN
      SELECT decision INTO v_decision
      FROM ai_make_decision(v_ai_player.id, p_universe_id);
      
      -- Log decision made
      PERFORM log_ai_action(
        v_ai_player.id,
        p_universe_id,
        'decision_made',
        'success',
        'Decision: ' || v_decision
      );
      
      -- Execute action
      SELECT result INTO v_action_result
      FROM ai_execute_action(v_ai_player.id, p_universe_id, v_decision);
      
      -- Log action execution
      PERFORM log_ai_action(
        v_ai_player.id,
        p_universe_id,
        'action_executed',
        CASE WHEN v_action_result THEN 'success' ELSE 'failed' END,
        'Decision: ' || v_decision || ', Result: ' || v_action_result
      );
      
      IF v_action_result THEN
        v_actions_taken := v_actions_taken + 1;
        
        -- Count specific action types
        CASE v_decision
          WHEN 'claim_planet' THEN
            v_planets_claimed := v_planets_claimed + 1;
          WHEN 'upgrade_ship', 'upgrade_weapons', 'upgrade_engines', 'buy_fighters' THEN
            v_upgrades := v_upgrades + 1;
          WHEN 'trade', 'emergency_trade' THEN
            v_trades := v_trades + 1;
        END CASE;
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      -- Log decision/action errors
      PERFORM log_ai_action(
        v_ai_player.id,
        p_universe_id,
        'action_error',
        'error',
        'Error: ' || SQLERRM || ', Decision: ' || COALESCE(v_decision, 'unknown')
      );
    END;
  END LOOP;

  -- Log end of AI run
  PERFORM log_ai_action(
    NULL, -- no specific player
    p_universe_id,
    'ai_run_end',
    'success',
    'Actions: ' || v_actions_taken || ', Players: ' || v_players_processed || ', Planets: ' || v_planets_claimed || ', Upgrades: ' || v_upgrades || ', Trades: ' || v_trades
  );

  -- Return results
  RETURN jsonb_build_object(
    'success', true,
    'message', 'ok',
    'actions_taken', v_actions_taken,
    'players_processed', v_players_processed,
    'planets_claimed', v_planets_claimed,
    'upgrades', v_upgrades,
    'trades', v_trades
  );
END;
$$;
