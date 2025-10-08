-- Migration: 314_fix_ai_trading_logic.sql
-- Purpose: Fix AI to only trade at commodity ports and prioritize goods/ore

CREATE OR REPLACE FUNCTION public.ai_make_decision(p_player_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_credits bigint;
  v_turns int;
  v_sector_id uuid;
  v_planets_count int;
  v_commodity_ports_count int;
  v_special_ports_count int;
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
  
  -- Get sector info - count commodity ports vs special ports
  SELECT 
    (SELECT COUNT(*) FROM public.planets pl WHERE pl.sector_id = v_sector_id AND pl.owner_player_id IS NULL) as unclaimed_planets,
    (SELECT COUNT(*) FROM public.ports pr WHERE pr.sector_id = v_sector_id AND pr.kind = 'trade') as commodity_ports,
    (SELECT COUNT(*) FROM public.ports pr WHERE pr.sector_id = v_sector_id AND pr.kind = 'special') as special_ports
  INTO v_planets_count, v_commodity_ports_count, v_special_ports_count;
  
  -- Decision logic with detailed logging
  IF v_turns <= 0 THEN
    v_decision := 'wait';
  ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
  ELSIF v_commodity_ports_count > 0 AND v_credits >= 500 THEN
    v_decision := 'trade';
  ELSE
    v_decision := 'explore';
  END IF;
  
  RETURN v_decision;
END;
$$;

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
  v_port_kind text;
  v_port_ore int;
  v_port_goods int;
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
      -- Find first COMMODITY port in current sector (not special port)
      SELECT id, kind, ore, goods INTO v_port_id, v_port_kind, v_port_ore, v_port_goods
      FROM public.ports
      WHERE sector_id = v_sector_id AND kind = 'trade'
      LIMIT 1;
      
      IF v_port_id IS NOT NULL THEN
        BEGIN
          -- game_trade returns JSON, check if it contains success
          DECLARE
            v_trade_result json;
            v_resource_to_trade text;
          BEGIN
            -- Prioritize goods and ore (most profitable)
            IF v_port_goods > 0 THEN
              v_resource_to_trade := 'goods';
            ELSIF v_port_ore > 0 THEN
              v_resource_to_trade := 'ore';
            ELSE
              v_resource_to_trade := 'organics'; -- fallback
            END IF;
            
            -- FIXED: Use v_user_id instead of p_player_id
            SELECT public.game_trade(v_user_id, v_port_id, 'buy', v_resource_to_trade, 1, p_universe_id) INTO v_trade_result;
            
            -- Log the trade result for debugging
            PERFORM log_ai_action(
              p_player_id,
              p_universe_id,
              'trade_result',
              'info',
              'Trade result for ' || v_player_handle || ': ' || v_trade_result::text || ' (tried ' || v_resource_to_trade || ')'
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
        -- Log when no commodity port found
        PERFORM log_ai_action(
          p_player_id,
          p_universe_id,
          'no_commodity_port',
          'error',
          'No commodity port found in sector for ' || v_player_handle || ' | Sector: ' || v_sector_id
        );
        v_result := false;
      END IF;
      
    WHEN 'explore' THEN
      -- Move to random connected sector
      BEGIN
        SELECT w.to_sector INTO v_sector_id
        FROM public.warps w
        WHERE w.from_sector = (SELECT current_sector FROM public.players WHERE id = p_player_id)
        ORDER BY RANDOM()
        LIMIT 1;
        
        IF v_sector_id IS NOT NULL THEN
          SELECT number INTO v_sector_number FROM public.sectors WHERE id = v_sector_id;
          IF v_sector_number IS NOT NULL THEN
            DECLARE
              v_move_result json;
            BEGIN
              -- FIXED: Use v_user_id instead of p_player_id
              SELECT public.game_move(v_user_id, v_sector_number, p_universe_id) INTO v_move_result;
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
