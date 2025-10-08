-- Migration: 312_fix_ai_trade_user_id.sql
-- Purpose: Fix AI trade function to use user_id instead of player_id

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
  v_user_id uuid;
BEGIN
  -- Get player handle and user_id for logging and function calls
  SELECT handle, user_id INTO v_player_handle, v_user_id 
  FROM public.players 
  WHERE id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  
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
            -- FIXED: Use v_user_id instead of p_player_id
            SELECT public.game_trade(v_user_id, v_port_id, 'buy', 'ore', 1, p_universe_id) INTO v_trade_result;
            
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
