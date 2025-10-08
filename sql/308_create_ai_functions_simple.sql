-- Migration: 308_create_ai_functions_simple.sql
-- Purpose: Create AI functions with simpler syntax

-- Drop existing functions if they exist
DROP FUNCTION IF EXISTS public.ai_make_decision(uuid);
DROP FUNCTION IF EXISTS public.ai_execute_action(uuid, uuid, text);

-- Create ai_make_decision function
CREATE OR REPLACE FUNCTION public.ai_make_decision(p_player_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_credits bigint;
  v_turns int;
  v_decision text;
BEGIN
  -- Get basic player info
  SELECT s.credits, COALESCE(p.turns, 0)
  INTO v_credits, v_turns
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN 'wait';
  END IF;
  
  -- Simple decision logic
  IF v_turns <= 0 THEN
    v_decision := 'wait';
  ELSIF v_credits >= 1000 THEN
    v_decision := 'claim_planet';
  ELSIF v_credits >= 500 THEN
    v_decision := 'trade';
  ELSE
    v_decision := 'explore';
  END IF;
  
  RETURN v_decision;
END;
$$;

-- Create ai_execute_action function
CREATE OR REPLACE FUNCTION public.ai_execute_action(p_player_id uuid, p_universe_id uuid, p_action text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_result boolean := false;
  v_sector_id uuid;
  v_planet_id uuid;
  v_port_id uuid;
BEGIN
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
          SELECT result INTO v_result
          FROM public.game_planet_claim(p_player_id, v_planet_id, p_universe_id);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
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
          SELECT result INTO v_result
          FROM public.game_trade(p_player_id, v_port_id, 'buy', 'ore', 1, p_universe_id);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
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
          SELECT result INTO v_result
          FROM public.game_move(p_player_id, (SELECT number FROM public.sectors WHERE id = v_sector_id), p_universe_id);
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
