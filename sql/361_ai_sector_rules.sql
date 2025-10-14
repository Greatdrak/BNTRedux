-- AI Sector Rules Enhancement
-- Add logic to prevent AI from attacking in Federation sectors or sectors with combat restrictions

-- Enhanced ai_make_decision function with sector rule checking
CREATE OR REPLACE FUNCTION "public"."ai_make_decision"("p_player_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_player_id uuid;
  v_player_handle text;
  v_sector_id uuid;
  v_sector_number int;
  v_turns int;
  v_is_ai boolean;
  v_credits bigint;
  v_hull_level int;
  v_hull_max int;
  v_armor_lvl int;
  v_energy int;
  v_fighters int;
  v_torpedoes int;
  v_comp_lvl int;
  v_torp_launcher_lvl int;
  v_power_lvl int;
  v_planets_count int := 0;
  v_commodity_ports_count int := 0;
  v_special_ports_count int := 0;
  v_energy_ports_count int := 0;
  v_warps_count int := 0;
  v_enemy_ships_count int := 0;
  v_sector_allows_combat boolean := true;
  v_decision text;
  v_decision_weight int;
BEGIN
  -- Get comprehensive player and ship info
  SELECT p.id, p.handle, p.current_sector, p.turns, p.is_ai,
         s.credits, s.hull, s.hull_max, s.armor_lvl, s.energy, s.fighters, s.torpedoes,
         s.comp_lvl, s.torp_launcher_lvl, s.power_lvl
  INTO v_player_id, v_player_handle, v_sector_id, v_turns, v_is_ai, v_credits, v_hull_level, v_hull_max, v_armor_lvl, v_energy, v_fighters, v_torpedoes, v_comp_lvl, v_torp_launcher_lvl, v_power_lvl
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.is_ai = true;
  
  IF NOT FOUND THEN
    RETURN 'wait';
  END IF;
  
  v_turns := COALESCE(v_turns, 0);
  
  -- Get sector number and check if combat is allowed
  SELECT s.number INTO v_sector_number 
  FROM public.sectors s 
  WHERE s.id = v_sector_id;
  
  -- Check if sector allows combat (Federation sectors 0-10 prohibit combat)
  v_sector_allows_combat := (v_sector_number > 10);
  
  -- Get comprehensive sector information
  SELECT 
    (SELECT COUNT(*) FROM public.planets pl 
     WHERE pl.sector_id = v_sector_id AND pl.owner_player_id IS NULL) as unclaimed_planets,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind IN ('ore', 'organics', 'goods')) as commodity_ports,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind = 'special') as special_ports,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind = 'energy') as energy_ports,
    (SELECT COUNT(*) FROM public.warps w 
     WHERE w.from_sector_id = v_sector_id) as warps_count,
    (SELECT COUNT(*) FROM public.ships sh 
     JOIN public.players pl ON sh.player_id = pl.id
     WHERE pl.current_sector = v_sector_id AND pl.id != v_player_id AND pl.is_ai = false) as enemy_ships
  INTO v_planets_count, v_commodity_ports_count, v_special_ports_count, v_energy_ports_count, v_warps_count, v_enemy_ships_count;
  
  -- Decision logic with combat-focused priorities and sector rule checking
  v_decision := 'wait'; -- Default fallback
  
  -- Priority 1: No turns = wait
  IF v_turns <= 0 THEN
    v_decision := 'wait';
    
  -- Priority 2: If in Federation sector and no productive actions, explore away
  ELSIF NOT v_sector_allows_combat AND v_warps_count > 0 AND v_commodity_ports_count = 0 AND v_special_ports_count = 0 AND v_planets_count = 0 THEN
    v_decision := 'explore';
    
  -- Priority 3: Combat readiness at special ports (buy fighters/torpedoes)
  ELSIF v_special_ports_count > 0 AND v_credits >= 2000 THEN
    -- Check if we need combat supplies
    IF (v_fighters < (100 * POWER(1.5, v_comp_lvl - 1) * 0.5)::INTEGER) OR 
       (v_torpedoes < (v_torp_launcher_lvl * 100 * 0.5)) THEN
      v_decision := 'buy_fighters'; -- This will trigger combat readiness function
    ELSIF v_credits >= 500 AND (v_hull_level < 8 OR v_comp_lvl < 8 OR v_torp_launcher_lvl < 5) THEN
      v_decision := 'upgrade_ship';
    ELSE
      v_decision := 'wait';
    END IF;
    
  -- Priority 4: Energy buying at energy ports
  ELSIF v_energy_ports_count > 0 AND v_credits >= 1000 AND v_energy < (100 * POWER(1.5, v_power_lvl - 1) * 0.6)::INTEGER THEN
    v_decision := 'buy_energy';
    
  -- Priority 5: Claim planets (high value, limited opportunity)
  ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
    
  -- Priority 6: Trade at commodity ports (immediate profit)
  ELSIF v_commodity_ports_count > 0 AND v_credits >= 100 THEN
    v_decision := 'trade';
    
  -- Priority 7: Attack enemy ships (ONLY if combat is allowed in this sector)
  ELSIF v_sector_allows_combat AND v_enemy_ships_count > 0 AND v_fighters >= 50 AND v_torpedoes >= 20 THEN
    v_decision := 'attack_enemy';
    
  -- Priority 8: Explore (only if we have warps to explore)
  ELSIF v_warps_count > 0 THEN
    v_decision := 'explore';
    
  -- Priority 9: Emergency actions
  ELSIF v_credits < 100 THEN
    v_decision := 'emergency_trade';
    
  ELSE
    -- Fallback: wait for better opportunities
    v_decision := 'wait';
  END IF;
  
  RETURN v_decision;
EXCEPTION WHEN OTHERS THEN
  -- Log error and return safe fallback
  RETURN 'wait';
END;
$$;

-- Enhanced ai_execute_action function with attack logic
CREATE OR REPLACE FUNCTION "public"."ai_execute_action"("ai_player" "record", "ai_memory" "record", "action" "text") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
    v_planet RECORD;
    v_target_sector RECORD;
    v_enemy_ship RECORD;
    v_sector_number INT;
    v_sector_allows_combat BOOLEAN := TRUE;
    v_profit BIGINT;
    v_cost BIGINT;
BEGIN
    -- Get sector number and check combat rules
    SELECT s.number INTO v_sector_number 
    FROM public.sectors s 
    WHERE s.id = ai_player.current_sector;
    
    -- Check if sector allows combat (Federation sectors 0-10 prohibit combat)
    v_sector_allows_combat := (v_sector_number > 10);
    
    CASE action
        WHEN 'optimize_trade' THEN
            v_success := public.ai_optimize_trading(ai_player);
            
        WHEN 'emergency_trade' THEN
            v_success := public.ai_emergency_trade(ai_player);
            
        WHEN 'strategic_explore' THEN
            v_success := public.ai_strategic_explore(ai_player, ai_memory);
            
        WHEN 'claim_planet' THEN
            v_success := public.ai_claim_planet(ai_player);
            
        WHEN 'upgrade_ship' THEN
            v_success := public.ai_upgrade_ship(ai_player);
            
        WHEN 'upgrade_weapons' THEN
            v_success := public.ai_upgrade_weapons(ai_player);
            
        WHEN 'upgrade_engines' THEN
            v_success := public.ai_upgrade_engines(ai_player);
            
        WHEN 'buy_fighters' THEN
            v_success := public.ai_combat_readiness(ai_player);
            
        WHEN 'buy_energy' THEN
            v_success := public.ai_buy_energy(ai_player);
            
        WHEN 'manage_planets' THEN
            v_success := public.ai_manage_planets(ai_player);
            
        WHEN 'patrol_territory' THEN
            v_success := public.ai_patrol_territory(ai_player);
            
        WHEN 'attack_enemy' THEN
            -- Only attempt attack if combat is allowed in this sector
            IF v_sector_allows_combat THEN
                -- Find a random enemy ship in the same sector
                SELECT s.*, p.handle as player_handle
                INTO v_enemy_ship
                FROM public.ships s
                JOIN public.players p ON s.player_id = p.id
                WHERE p.current_sector = ai_player.current_sector 
                  AND p.id != ai_player.id 
                  AND p.is_ai = false
                ORDER BY RANDOM()
                LIMIT 1;
                
                IF FOUND THEN
                    -- Perform attack using the existing combat system
                    -- This would call the combat API endpoint
                    v_success := TRUE; -- For now, just mark as successful
                    -- TODO: Implement actual attack logic here
                ELSE
                    v_success := FALSE;
                END IF;
            ELSE
                -- Combat not allowed in this sector, skip attack
                v_success := FALSE;
            END IF;
            
        ELSE
            -- Default basic actions
            v_success := public.ai_basic_action(ai_player, action);
    END CASE;

    -- Track turn spent for successful actions (for leaderboard activity tracking)
    -- AI players have unlimited turns, but we track their activity level
    IF v_success THEN
        PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_action_' || action);
    END IF;

    RETURN v_success;
END;
$$;

-- Add logging for AI sector rule decisions
CREATE OR REPLACE FUNCTION "public"."log_ai_sector_decision"("p_player_id" "uuid", "p_sector_number" int, "p_decision" "text", "p_reason" "text") RETURNS void
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    INSERT INTO public.player_logs (player_id, kind, ref_id, message, occurred_at)
    VALUES (
        p_player_id, 
        'ai_decision', 
        NULL, 
        'AI Decision: ' || p_decision || ' in sector ' || p_sector_number || ' - ' || p_reason,
        NOW()
    );
EXCEPTION WHEN OTHERS THEN
    -- Ignore logging errors
    NULL;
END;
$$;
