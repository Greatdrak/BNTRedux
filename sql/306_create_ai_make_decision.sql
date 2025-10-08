-- Migration: 306_create_ai_make_decision.sql
-- Purpose: Create the missing ai_make_decision function

CREATE OR REPLACE FUNCTION public.ai_make_decision(p_player_id uuid, p_universe_id uuid)
RETURNS TABLE(decision text)
LANGUAGE plpgsql
AS $$
DECLARE
  v_player record;
  v_ship record;
  v_sector record;
  v_planets_count int;
  v_ports_count int;
  v_credits bigint;
  v_turns int;
  v_decision text;
BEGIN
  -- Get player and ship info
  SELECT p.*, s.credits, s.hull, s.armor, s.energy, s.fighters, s.torpedoes
  INTO v_player, v_ship
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  IF NOT FOUND THEN
    decision := 'wait';
    RETURN NEXT;
    RETURN;
  END IF;
  
  -- Get sector info
  SELECT s.*, 
    (SELECT COUNT(*) FROM public.planets pl WHERE pl.sector_id = s.id AND pl.owner_id IS NULL) as unclaimed_planets,
    (SELECT COUNT(*) FROM public.ports pr WHERE pr.sector_id = s.id) as ports_count
  INTO v_sector
  FROM public.sectors s
  WHERE s.id = v_player.current_sector;
  
  v_credits := v_ship.credits;
  v_turns := COALESCE(v_player.turns, 0);
  
  -- Simple decision logic based on current state
  IF v_turns <= 0 THEN
    v_decision := 'wait';
  ELSIF v_sector.unclaimed_planets > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
  ELSIF v_sector.ports_count > 0 AND v_credits >= 500 THEN
    v_decision := 'trade';
  ELSIF v_ship.hull < 50 OR v_ship.armor < 10 THEN
    v_decision := 'upgrade_ship';
  ELSIF v_ship.fighters < 10 THEN
    v_decision := 'buy_fighters';
  ELSIF v_credits < 1000 THEN
    v_decision := 'trade';
  ELSE
    v_decision := 'explore';
  END IF;
  
  decision := v_decision;
  RETURN NEXT;
END;
$$;
