-- Migration: 324_disable_ai_logging.sql
-- Purpose: Disable AI action logging to improve performance

-- Drop existing functions first
DROP FUNCTION IF EXISTS public.run_ai_player_actions(uuid);
DROP FUNCTION IF EXISTS public.ai_execute_action(uuid, uuid, text);

-- Update run_ai_player_actions to remove all logging calls
CREATE OR REPLACE FUNCTION public.run_ai_player_actions(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_player RECORD;
  v_decision text;
  v_result boolean;
  v_actions_taken int := 0;
  v_players_processed int := 0;
  v_trades int := 0;
  v_upgrades int := 0;
  v_planets_claimed int := 0;
BEGIN
  -- Loop through all AI players in the universe
  FOR v_player IN 
    SELECT 
      p.id as player_id,
      p.user_id,
      p.handle
    FROM public.players p
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = true
      AND p.turns > 0
  LOOP
    v_players_processed := v_players_processed + 1;
    
    -- Make a decision for this AI player
    v_decision := ai_make_decision(v_player.player_id, p_universe_id);
    
    -- Execute the action
    v_result := ai_execute_action(v_player.player_id, p_universe_id, v_decision);
    
    IF v_result THEN
      v_actions_taken := v_actions_taken + 1;
      
      -- Track action type for stats
      CASE v_decision
        WHEN 'trade' THEN v_trades := v_trades + 1;
        WHEN 'upgrade' THEN v_upgrades := v_upgrades + 1;
        WHEN 'claim_planet' THEN v_planets_claimed := v_planets_claimed + 1;
        ELSE NULL;
      END CASE;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'ok',
    'players_processed', v_players_processed,
    'actions_taken', v_actions_taken,
    'trades', v_trades,
    'upgrades', v_upgrades,
    'planets_claimed', v_planets_claimed
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Failed to run AI player actions: ' || SQLERRM
  );
END;
$$;

-- Update ai_execute_action to remove all logging calls
CREATE OR REPLACE FUNCTION public.ai_execute_action(
  p_player_id uuid,
  p_universe_id uuid,
  p_decision text
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_result boolean := false;
  v_user_id uuid;
  v_player_handle text;
  v_sector_id uuid;
  v_sector_num int;
  v_port_id uuid;
  v_port_kind text;
  v_sector_number int;
  v_claim_result jsonb;
  v_trade_result jsonb;
  v_move_result jsonb;
  v_available_sectors int[];
BEGIN
  -- Get player info
  SELECT user_id, handle, current_sector 
  INTO v_user_id, v_player_handle, v_sector_id
  FROM public.players 
  WHERE id = p_player_id;

  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  -- Execute based on decision
  CASE p_decision
    WHEN 'claim_planet' THEN
      -- Get current sector number
      SELECT number INTO v_sector_num
      FROM public.sectors
      WHERE id = v_sector_id;
      
      -- Attempt to claim a planet in the current sector
      SELECT public.game_planet_claim(v_user_id, v_sector_num, 'AI Colony', p_universe_id) INTO v_claim_result;
      
      v_result := (v_claim_result->>'success')::boolean;

    WHEN 'trade' THEN
      -- Find a commodity port in current sector (not special port)
      SELECT p.id, p.kind 
      INTO v_port_id, v_port_kind
      FROM public.ports p
      WHERE p.sector_id = v_sector_id
        AND p.kind IN ('ore', 'organics', 'goods', 'energy')
      LIMIT 1;

      IF v_port_id IS NOT NULL THEN
        -- Execute a simple trade (buy ore as an example)
        SELECT public.game_trade(v_user_id, v_port_id, 'buy', 'ore', 1, p_universe_id) INTO v_trade_result;
        
        v_result := COALESCE((v_trade_result->>'success')::boolean, false);
      END IF;

    WHEN 'explore' THEN
      -- Get available warps from current sector
      SELECT ARRAY_AGG(s.number)
      INTO v_available_sectors
      FROM public.warps w
      JOIN public.sectors s ON s.id = w.to_sector
      WHERE w.from_sector = v_sector_id
      LIMIT 10;

      IF v_available_sectors IS NOT NULL AND array_length(v_available_sectors, 1) > 0 THEN
        -- Pick a random connected sector
        v_sector_number := v_available_sectors[1 + floor(random() * array_length(v_available_sectors, 1))::int];
        
        -- Move to that sector
        SELECT public.game_move(v_user_id, v_sector_number, p_universe_id) INTO v_move_result;
        
        v_result := (v_move_result->>'ok')::boolean;
      END IF;

    ELSE
      -- Unknown decision
      v_result := false;
  END CASE;

  RETURN v_result;
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;

