-- Advanced AI System with Strategic Planning and Multi-Turn Actions
-- This mimics how human players actually play the game

-- 1. Create AI personality types and strategic goals
CREATE OR REPLACE FUNCTION public.ai_get_personality_type(p_player_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_handle text;
  v_personality text;
BEGIN
  -- Get player handle to determine personality
  SELECT handle INTO v_handle
  FROM public.players
  WHERE id = p_player_id;
  
  -- Assign personality based on handle keywords
  IF v_handle ILIKE '%trader%' OR v_handle ILIKE '%merchant%' OR v_handle ILIKE '%commerce%' THEN
    v_personality := 'trader';
  ELSIF v_handle ILIKE '%explorer%' OR v_handle ILIKE '%scout%' OR v_handle ILIKE '%wanderer%' THEN
    v_personality := 'explorer';
  ELSIF v_handle ILIKE '%warrior%' OR v_handle ILIKE '%fighter%' OR v_handle ILIKE '%combat%' THEN
    v_personality := 'warrior';
  ELSIF v_handle ILIKE '%colonizer%' OR v_handle ILIKE '%builder%' OR v_handle ILIKE '%settler%' THEN
    v_personality := 'colonizer';
  ELSE
    v_personality := 'balanced';
  END IF;
  
  RETURN v_personality;
END;
$$;

-- 2. Advanced AI decision making with strategic planning
CREATE OR REPLACE FUNCTION public.ai_make_strategic_decision(p_player_id uuid, p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_player_id uuid;
  v_player_handle text;
  v_sector_id uuid;
  v_turns int;
  v_credits bigint;
  v_hull_level int;
  v_hull_max int;
  v_cargo_ore int;
  v_cargo_organics int;
  v_cargo_goods int;
  v_cargo_energy int;
  v_personality text;
  v_planets_count int := 0;
  v_commodity_ports_count int := 0;
  v_special_ports_count int := 0;
  v_warps_count int := 0;
  v_owned_planets int := 0;
  v_decision jsonb;
  v_priority_score int;
BEGIN
  -- Get comprehensive player and ship info
  SELECT p.id, p.handle, p.current_sector, p.turns, p.is_ai,
         s.credits, s.hull, s.hull_max, s.ore, s.organics, s.goods, s.energy
  INTO v_player_id, v_player_handle, v_sector_id, v_turns, v_credits, v_hull_level, v_hull_max, v_cargo_ore, v_cargo_organics, v_cargo_goods, v_cargo_energy
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.is_ai = true;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('action', 'wait', 'reason', 'player_not_found');
  END IF;
  
  v_turns := COALESCE(v_turns, 0);
  v_personality := ai_get_personality_type(p_player_id);
  
  -- Get comprehensive sector and player information
  SELECT 
    (SELECT COUNT(*) FROM public.planets pl 
     WHERE pl.sector_id = v_sector_id AND pl.owner_player_id IS NULL) as unclaimed_planets,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind IN ('ore', 'organics', 'goods', 'energy')) as commodity_ports,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind = 'special') as special_ports,
    (SELECT COUNT(*) FROM public.warps w 
     WHERE w.from_sector_id = v_sector_id) as warps_count,
    (SELECT COUNT(*) FROM public.planets pl 
     WHERE pl.owner_player_id = v_player_id) as owned_planets
  INTO v_planets_count, v_commodity_ports_count, v_special_ports_count, v_warps_count, v_owned_planets;
  
  -- Strategic decision making based on personality and situation
  CASE v_personality
    WHEN 'trader' THEN
      -- Traders focus on profit and cargo management
      IF v_turns >= 10 AND v_commodity_ports_count > 0 AND v_cargo_ore + v_cargo_organics + v_cargo_goods + v_cargo_energy < 100 THEN
        v_decision := jsonb_build_object(
          'action', 'trade_route',
          'turns_to_spend', LEAST(v_turns, 20),
          'reason', 'trader_building_cargo',
          'priority', 90
        );
      ELSIF v_turns >= 5 AND v_warps_count > 0 AND (v_cargo_ore + v_cargo_organics + v_cargo_goods + v_cargo_energy) > 50 THEN
        v_decision := jsonb_build_object(
          'action', 'explore_sell',
          'turns_to_spend', LEAST(v_turns, 10),
          'reason', 'trader_finding_markets',
          'priority', 80
        );
      ELSIF v_credits >= 5000 AND v_special_ports_count > 0 AND v_hull_level < 10 THEN
        v_decision := jsonb_build_object(
          'action', 'upgrade_ship',
          'turns_to_spend', 1,
          'reason', 'trader_upgrading_capacity',
          'priority', 70
        );
      ELSE
        v_decision := jsonb_build_object(
          'action', 'explore',
          'turns_to_spend', LEAST(v_turns, 5),
          'reason', 'trader_exploring',
          'priority', 60
        );
      END IF;
      
    WHEN 'explorer' THEN
      -- Explorers focus on discovery and mapping
      IF v_turns >= 15 AND v_warps_count > 0 THEN
        v_decision := jsonb_build_object(
          'action', 'explore_deep',
          'turns_to_spend', LEAST(v_turns, 30),
          'reason', 'explorer_mapping',
          'priority', 95
        );
      ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
        v_decision := jsonb_build_object(
          'action', 'claim_planet',
          'turns_to_spend', 1,
          'reason', 'explorer_claiming',
          'priority', 85
        );
      ELSIF v_credits >= 2000 AND v_special_ports_count > 0 AND v_hull_level < 8 THEN
        v_decision := jsonb_build_object(
          'action', 'upgrade_ship',
          'turns_to_spend', 1,
          'reason', 'explorer_upgrading',
          'priority', 75
        );
      ELSE
        v_decision := jsonb_build_object(
          'action', 'explore',
          'turns_to_spend', LEAST(v_turns, 10),
          'reason', 'explorer_moving',
          'priority', 70
        );
      END IF;
      
    WHEN 'warrior' THEN
      -- Warriors focus on combat and territorial control
      IF v_credits >= 3000 AND v_special_ports_count > 0 AND v_hull_level < 15 THEN
        v_decision := jsonb_build_object(
          'action', 'upgrade_ship',
          'turns_to_spend', 1,
          'reason', 'warrior_upgrading',
          'priority', 90
        );
      ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
        v_decision := jsonb_build_object(
          'action', 'claim_planet',
          'turns_to_spend', 1,
          'reason', 'warrior_claiming',
          'priority', 80
        );
      ELSIF v_turns >= 10 AND v_warps_count > 0 THEN
        v_decision := jsonb_build_object(
          'action', 'patrol',
          'turns_to_spend', LEAST(v_turns, 20),
          'reason', 'warrior_patrolling',
          'priority', 70
        );
      ELSE
        v_decision := jsonb_build_object(
          'action', 'explore',
          'turns_to_spend', LEAST(v_turns, 5),
          'reason', 'warrior_scouting',
          'priority', 60
        );
      END IF;
      
    WHEN 'colonizer' THEN
      -- Colonizers focus on planet development and expansion
      IF v_planets_count > 0 AND v_credits >= 1000 THEN
        v_decision := jsonb_build_object(
          'action', 'claim_planet',
          'turns_to_spend', 1,
          'reason', 'colonizer_expanding',
          'priority', 95
        );
      ELSIF v_owned_planets > 0 AND v_credits >= 2000 THEN
        v_decision := jsonb_build_object(
          'action', 'develop_planets',
          'turns_to_spend', LEAST(v_turns, 15),
          'reason', 'colonizer_developing',
          'priority', 85
        );
      ELSIF v_credits >= 3000 AND v_special_ports_count > 0 AND v_hull_level < 12 THEN
        v_decision := jsonb_build_object(
          'action', 'upgrade_ship',
          'turns_to_spend', 1,
          'reason', 'colonizer_upgrading',
          'priority', 75
        );
      ELSE
        v_decision := jsonb_build_object(
          'action', 'explore',
          'turns_to_spend', LEAST(v_turns, 8),
          'reason', 'colonizer_seeking',
          'priority', 65
        );
      END IF;
      
    ELSE -- balanced
      -- Balanced players adapt to current situation
      IF v_credits < 500 THEN
        v_decision := jsonb_build_object(
          'action', 'emergency_trade',
          'turns_to_spend', LEAST(v_turns, 10),
          'reason', 'balanced_emergency',
          'priority', 100
        );
      ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
        v_decision := jsonb_build_object(
          'action', 'claim_planet',
          'turns_to_spend', 1,
          'reason', 'balanced_claiming',
          'priority', 80
        );
      ELSIF v_turns >= 20 AND v_commodity_ports_count > 0 THEN
        v_decision := jsonb_build_object(
          'action', 'trade_route',
          'turns_to_spend', LEAST(v_turns, 25),
          'reason', 'balanced_trading',
          'priority', 75
        );
      ELSIF v_credits >= 2000 AND v_special_ports_count > 0 AND v_hull_level < 10 THEN
        v_decision := jsonb_build_object(
          'action', 'upgrade_ship',
          'turns_to_spend', 1,
          'reason', 'balanced_upgrading',
          'priority', 70
        );
      ELSE
        v_decision := jsonb_build_object(
          'action', 'explore',
          'turns_to_spend', LEAST(v_turns, 10),
          'reason', 'balanced_exploring',
          'priority', 60
        );
      END IF;
  END CASE;
  
  RETURN v_decision;
END;
$$;
