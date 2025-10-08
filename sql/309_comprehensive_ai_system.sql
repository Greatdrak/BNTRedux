-- Migration: 309_comprehensive_ai_system.sql
-- Purpose: Create a complete, working AI system with full logging

-- 1. Create ai_player_memory table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.ai_player_memory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  current_goal text DEFAULT 'explore',
  target_sector_id uuid REFERENCES public.sectors(id),
  last_action text,
  action_count integer DEFAULT 0,
  efficiency_score numeric DEFAULT 0.0,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

-- Create unique constraint
CREATE UNIQUE INDEX IF NOT EXISTS ai_player_memory_player_id_key ON public.ai_player_memory(player_id);

-- 2. Create comprehensive log_ai_action function
CREATE OR REPLACE FUNCTION public.log_ai_action(
  p_player_id uuid,
  p_universe_id uuid,
  p_action text,
  p_outcome text,
  p_message text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.ai_action_log (
    player_id,
    universe_id,
    action,
    outcome,
    message,
    created_at
  ) VALUES (
    p_player_id,
    p_universe_id,
    p_action,
    p_outcome,
    p_message,
    NOW()
  );
EXCEPTION WHEN OTHERS THEN
  -- Silently ignore logging errors to prevent AI from failing
  NULL;
END;
$$;

-- 3. Create ai_make_decision function with DEEP LOGGING
CREATE OR REPLACE FUNCTION public.ai_make_decision(p_player_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_credits bigint;
  v_turns int;
  v_sector_id uuid;
  v_planets_count int;
  v_ports_count int;
  v_decision text;
  v_player_handle text;
BEGIN
  -- Get player and ship info
  SELECT s.credits, COALESCE(p.turns, 0), p.current_sector, p.handle
  INTO v_credits, v_turns, v_sector_id, v_player_handle
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN 'wait';
  END IF;
  
  -- Get sector info
  SELECT 
    (SELECT COUNT(*) FROM public.planets pl WHERE pl.sector_id = v_sector_id AND pl.owner_player_id IS NULL) as unclaimed_planets,
    (SELECT COUNT(*) FROM public.ports pr WHERE pr.sector_id = v_sector_id) as ports_count
  INTO v_planets_count, v_ports_count;
  
  -- Decision logic with detailed logging
  IF v_turns <= 0 THEN
    v_decision := 'wait';
  ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
  ELSIF v_ports_count > 0 AND v_credits >= 500 THEN
    v_decision := 'trade';
  ELSE
    v_decision := 'explore';
  END IF;
  
  RETURN v_decision;
END;
$$;

-- 4. Create ai_execute_action function with DEEP LOGGING
CREATE OR REPLACE FUNCTION public.ai_execute_action(p_player_id uuid, p_universe_id uuid, p_action text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_result boolean := false;
  v_sector_id uuid;
  v_planet_id uuid;
  v_port_id uuid;
  v_sector_number int;
  v_player_handle text;
BEGIN
  -- Get player handle for logging
  SELECT handle INTO v_player_handle FROM public.players WHERE id = p_player_id;
  
  -- Get current sector
  SELECT current_sector INTO v_sector_id
  FROM public.players
  WHERE id = p_player_id;
  
  CASE p_action
    WHEN 'claim_planet' THEN
      -- Find first unclaimed planet in current sector
      SELECT id INTO v_planet_id
      FROM public.planets
      WHERE sector_id = v_sector_id AND owner_player_id IS NULL
      LIMIT 1;
      
      IF v_planet_id IS NOT NULL THEN
        BEGIN
          -- Get sector number for the claim function
          DECLARE
            v_sector_num int;
            v_claim_result json;
          BEGIN
            SELECT number INTO v_sector_num FROM public.sectors WHERE id = v_sector_id;
            SELECT public.game_planet_claim(p_player_id, v_sector_num, 'AI Colony', p_universe_id) INTO v_claim_result;
            v_result := (v_claim_result->>'success')::boolean;
          EXCEPTION WHEN OTHERS THEN
            v_result := false;
          END;
        END;
      END IF;
      
    WHEN 'trade' THEN
      -- Find first port in current sector
      SELECT id INTO v_port_id
      FROM public.ports
      WHERE sector_id = v_sector_id
      LIMIT 1;
      
      IF v_port_id IS NOT NULL THEN
        BEGIN
          -- game_trade returns JSON, check if it contains success
          DECLARE
            v_trade_result json;
          BEGIN
            SELECT public.game_trade(p_player_id, v_port_id, 'buy', 'ore', 1, p_universe_id) INTO v_trade_result;
            
            -- Log the trade result for debugging
            PERFORM log_ai_action(
              p_player_id,
              p_universe_id,
              'trade_result',
              'info',
              'Trade result for ' || v_player_handle || ': ' || v_trade_result::text
            );
            
            v_result := (v_trade_result->>'success')::boolean;
          EXCEPTION WHEN OTHERS THEN
            -- Log the specific error
            PERFORM log_ai_action(
              p_player_id,
              p_universe_id,
              'trade_error',
              'error',
              'Trade failed for ' || v_player_handle || ': ' || SQLERRM || ' | Port: ' || v_port_id
            );
            v_result := false;
          END;
        END;
      ELSE
        -- Log when no port found
        PERFORM log_ai_action(
          p_player_id,
          p_universe_id,
          'no_port_found',
          'error',
          'No port found in sector for ' || v_player_handle || ' | Sector: ' || v_sector_id
        );
        v_result := false;
      END IF;
      
    WHEN 'explore' THEN
      -- Move to random connected sector
      BEGIN
        SELECT w.to_sector_id INTO v_sector_id
        FROM public.warps w
        WHERE w.from_sector_id = (SELECT current_sector FROM public.players WHERE id = p_player_id)
        ORDER BY RANDOM()
        LIMIT 1;
        
        IF v_sector_id IS NOT NULL THEN
          SELECT number INTO v_sector_number FROM public.sectors WHERE id = v_sector_id;
          IF v_sector_number IS NOT NULL THEN
            DECLARE
              v_move_result json;
            BEGIN
              SELECT public.game_move(p_player_id, v_sector_number, p_universe_id) INTO v_move_result;
              v_result := (v_move_result->>'success')::boolean;
            EXCEPTION WHEN OTHERS THEN
              v_result := false;
            END;
          END IF;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_result := false;
      END;
      
    ELSE
      v_result := false;
  END CASE;
  
  RETURN v_result;
END;
$$;

-- 5. Create comprehensive run_ai_player_actions function with DEEP LOGGING
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
    '🚀 STARTING AI RUN FOR UNIVERSE: ' || p_universe_id
  );

  -- Count total AI players
  SELECT COUNT(*) INTO v_ai_count
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;

  -- Count AI players with turns
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;

  PERFORM log_ai_action(
    NULL,
    p_universe_id,
    'ai_count_check',
    'success',
    '📊 AI PLAYER COUNT: ' || v_ai_count || ' total, ' || v_ai_with_turns || ' with turns'
  );

  -- Process each AI player
  FOR v_ai_player IN 
    SELECT p.id, p.handle, p.current_sector, p.turns, p.is_ai,
           s.credits, s.hull, s.armor, s.energy, s.fighters, s.torpedoes,
           COALESCE(m.current_goal, 'explore') as current_goal,
           sec.number as sector_number
    FROM public.players p
    JOIN public.ships s ON s.player_id = p.id
    LEFT JOIN public.ai_player_memory m ON m.player_id = p.id
    LEFT JOIN public.sectors sec ON sec.id = p.current_sector
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = true
      AND COALESCE(p.turns, 0) > 0
  LOOP
    v_players_processed := v_players_processed + 1;
    
    -- Log detailed player processing start
    PERFORM log_ai_action(
      v_ai_player.id,
      p_universe_id,
      'player_process_start',
      'success',
      '🤖 PROCESSING AI: ' || v_ai_player.handle || 
      ' | Sector: ' || COALESCE(v_ai_player.sector_number::text, 'unknown') ||
      ' | Credits: ' || v_ai_player.credits ||
      ' | Turns: ' || v_ai_player.turns ||
      ' | Hull: ' || v_ai_player.hull ||
      ' | Goal: ' || v_ai_player.current_goal
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
        
        -- Count specific action types
        CASE v_decision
          WHEN 'claim_planet' THEN
            v_planets_claimed := v_planets_claimed + 1;
          WHEN 'trade' THEN
            v_trades := v_trades + 1;
        END CASE;

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

-- 6. Initialize AI memory for existing AI players
INSERT INTO public.ai_player_memory (player_id, current_goal)
SELECT p.id, 'explore'
FROM public.players p
WHERE p.is_ai = true
  AND NOT EXISTS (
    SELECT 1 FROM public.ai_player_memory m 
    WHERE m.player_id = p.id
  );
