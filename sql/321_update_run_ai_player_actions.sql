-- Migration: 321_update_run_ai_player_actions.sql
-- Purpose: Update run_ai_player_actions to work with the fixed ai_execute_action

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
  v_ai_count int;
  v_ai_with_turns int;
BEGIN
  -- Log start of AI run with universe details
  PERFORM log_ai_action(
    NULL,
    p_universe_id,
    'ai_run_start',
    'success',
    '🚀 AI RUN STARTED for universe: ' || p_universe_id
  );

  -- Get count of AI players
  SELECT COUNT(*) INTO v_ai_count
  FROM public.players
  WHERE universe_id = p_universe_id AND is_ai = true;

  -- Get count of AI players with turns
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players
  WHERE universe_id = p_universe_id AND is_ai = true AND turns > 0;

  -- Loop through all AI players in the universe with turns available
  FOR v_ai_player IN
    SELECT 
      p.id, 
      p.handle, 
      s.credits,
      p.turns, 
      p.current_sector,
      s.hull,
      m.current_goal
    FROM public.players p
    JOIN public.ships s ON s.player_id = p.id
    LEFT JOIN public.ai_player_memory m ON m.player_id = p.id
    WHERE p.universe_id = p_universe_id
      AND p.is_ai = true
      AND p.turns > 0
    ORDER BY p.id
    LIMIT 100 -- Safety limit
  LOOP
    v_players_processed := v_players_processed + 1;

    BEGIN
      -- Log player processing start with full details
      PERFORM log_ai_action(
        v_ai_player.id,
        p_universe_id,
        'player_process_start',
        'success',
        '🤖 PROCESSING AI: ' || v_ai_player.handle ||
        ' | Sector: ' || (SELECT number FROM public.sectors WHERE id = v_ai_player.current_sector) ||
        ' | Credits: ' || v_ai_player.credits ||
        ' | Turns: ' || v_ai_player.turns ||
        ' | Hull: ' || v_ai_player.hull ||
        ' | Goal: ' || COALESCE(v_ai_player.current_goal, 'none')
      );

      -- Make decision
      BEGIN
        PERFORM log_ai_action(
          v_ai_player.id,
          p_universe_id,
          'decision_start',
          'success',
          '🧠 STARTING DECISION PROCESS for ' || v_ai_player.handle
        );

        SELECT ai_make_decision(v_ai_player.id) INTO v_decision;
        
        -- Log decision made with reasoning
        PERFORM log_ai_action(
          v_ai_player.id,
          p_universe_id,
          'decision_made',
          'success',
          '✅ DECISION: ' || v_decision || ' for ' || v_ai_player.handle ||
          ' (Credits: ' || v_ai_player.credits || ', Turns: ' || v_ai_player.turns || ')'
        );
        
        -- Execute action
        PERFORM log_ai_action(
          v_ai_player.id,
          p_universe_id,
          'action_start',
          'success',
          '⚡ EXECUTING ACTION: ' || v_decision || ' for ' || v_ai_player.handle
        );

        SELECT ai_execute_action(v_ai_player.id, p_universe_id, v_decision) INTO v_action_result;
        
        -- Log action execution with detailed results
        PERFORM log_ai_action(
          v_ai_player.id,
          p_universe_id,
          'action_executed',
          CASE WHEN v_action_result THEN 'success' ELSE 'failed' END,
          '🎯 ACTION RESULT: ' || v_decision || ' = ' || 
          CASE WHEN v_action_result THEN 'SUCCESS' ELSE 'FAILED' END ||
          ' for ' || v_ai_player.handle
        );
        
        IF v_action_result THEN
          v_actions_taken := v_actions_taken + 1;
          
          -- Track specific action types
          IF v_decision = 'claim_planet' THEN
            v_planets_claimed := v_planets_claimed + 1;
          ELSIF v_decision = 'trade' THEN
            v_trades := v_trades + 1;
          END IF;
          
          -- Log successful action with celebration
          PERFORM log_ai_action(
            v_ai_player.id,
            p_universe_id,
            'action_success',
            'success',
            '🎉 SUCCESSFUL ACTION: ' || v_decision || ' completed by ' || v_ai_player.handle
          );
        ELSE
          PERFORM log_ai_action(
            v_ai_player.id,
            p_universe_id,
            'action_failed',
            'failed',
            '❌ FAILED ACTION: ' || v_decision || ' failed for ' || v_ai_player.handle
          );
        END IF;
        
      EXCEPTION WHEN OTHERS THEN
        -- Log decision/action errors with full details
        PERFORM log_ai_action(
          v_ai_player.id,
          p_universe_id,
          'action_error',
          'error',
          '💥 ERROR: ' || SQLERRM || ' | Decision: ' || COALESCE(v_decision, 'unknown') || ' | Player: ' || v_ai_player.handle
        );
      END;
    END;
  END LOOP;

  -- Log end of AI run with comprehensive stats
  PERFORM log_ai_action(
    NULL,
    p_universe_id,
    'ai_run_end',
    'success',
    '🏁 AI RUN COMPLETED: ' || v_actions_taken || ' actions, ' || v_players_processed || ' players processed, ' || v_planets_claimed || ' planets claimed, ' || v_trades || ' trades'
  );

  -- Return detailed results
  RETURN jsonb_build_object(
    'success', true,
    'message', 'AI run completed with ' || v_actions_taken || ' actions',
    'actions_taken', v_actions_taken,
    'players_processed', v_players_processed,
    'planets_claimed', v_planets_claimed,
    'upgrades', v_upgrades,
    'trades', v_trades,
    'ai_total', v_ai_count,
    'ai_with_turns', v_ai_with_turns
  );
END;
$$;
