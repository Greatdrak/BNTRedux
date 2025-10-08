-- Migration: 318_fix_ai_credit_priority.sql
-- Purpose: Fix AI decision logic to prioritize trading when credits are low

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
  
  -- IMPROVED Decision logic with credit priority
  IF v_turns <= 0 THEN
    v_decision := 'wait';
  ELSIF v_credits < 10000 THEN
    -- If low on credits, prioritize trading to earn money
    IF v_commodity_ports_count > 0 THEN
      v_decision := 'trade';
    ELSE
      v_decision := 'explore'; -- Move to find trading opportunities
    END IF;
  ELSIF v_planets_count > 0 AND v_credits >= 10000 THEN
    -- Only claim planets when we have enough credits
    v_decision := 'claim_planet';
  ELSIF v_commodity_ports_count > 0 AND v_credits >= 500 THEN
    -- Trade when we have commodity ports available
    v_decision := 'trade';
  ELSE
    -- Explore to find better opportunities
    v_decision := 'explore';
  END IF;
  
  RETURN v_decision;
END;
$$;
