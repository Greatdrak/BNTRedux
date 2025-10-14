-- AI Combat Improvements
-- Enhanced AI behavior for buying fighters, torpedoes, energy and prioritizing combat upgrades

-- Enhanced AI fighter buying function
CREATE OR REPLACE FUNCTION "public"."ai_buy_fighters"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_port RECORD;
    v_fighter_capacity INTEGER;
    v_fighters_to_buy INTEGER;
    v_cost BIGINT;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Check if we're at a special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- Calculate fighter capacity based on computer level
        v_fighter_capacity := (100 * POWER(1.5, ai_player.comp_lvl - 1))::INTEGER;
        
        -- Be more aggressive about buying fighters - buy up to 80% of capacity
        v_fighters_to_buy := LEAST(
            CEIL((v_fighter_capacity - ai_player.fighters) * 0.8),
            100 -- Increased max per purchase
        );
        
        -- Only buy if we have less than 50% of capacity
        IF ai_player.fighters < (v_fighter_capacity * 0.5) AND v_fighters_to_buy > 0 THEN
            v_cost := v_fighters_to_buy * 100; -- 100 credits per fighter
            
            -- Use up to 30% of credits for fighters if we have enough
            IF ai_player.credits >= v_cost AND ai_player.credits >= 2000 THEN
                UPDATE ships SET 
                    credits = credits - v_cost,
                    fighters = fighters + v_fighters_to_buy
                WHERE id = ai_player.ship_id;
                v_success := TRUE;
            END IF;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- New AI torpedo buying function
CREATE OR REPLACE FUNCTION "public"."ai_buy_torpedoes"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_port RECORD;
    v_torpedo_capacity INTEGER;
    v_torpedoes_to_buy INTEGER;
    v_cost BIGINT;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Check if we're at a special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- Calculate torpedo capacity based on torpedo launcher level
        v_torpedo_capacity := (ai_player.torp_launcher_lvl * 100);
        
        -- Buy torpedoes if we have less than 50% of capacity
        IF ai_player.torpedoes < (v_torpedo_capacity * 0.5) AND v_torpedo_capacity > 0 THEN
            v_torpedoes_to_buy := LEAST(
                CEIL((v_torpedo_capacity - ai_player.torpedoes) * 0.7),
                50 -- Max per purchase
            );
            
            v_cost := v_torpedoes_to_buy * 200; -- 200 credits per torpedo
            
            -- Use up to 25% of credits for torpedoes if we have enough
            IF ai_player.credits >= v_cost AND ai_player.credits >= 3000 THEN
                UPDATE ships SET 
                    credits = credits - v_cost,
                    torpedoes = torpedoes + v_torpedoes_to_buy
                WHERE id = ai_player.ship_id;
                v_success := TRUE;
            END IF;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- Enhanced AI energy buying function
CREATE OR REPLACE FUNCTION "public"."ai_buy_energy"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_port RECORD;
    v_energy_capacity INTEGER;
    v_energy_to_buy INTEGER;
    v_cost BIGINT;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Check if we're at an energy port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'energy';
    
    IF FOUND THEN
        -- Calculate energy capacity based on power level
        v_energy_capacity := (100 * POWER(1.5, ai_player.power_lvl - 1))::INTEGER;
        
        -- Buy energy if we have less than 60% of capacity
        IF ai_player.energy < (v_energy_capacity * 0.6) AND v_energy_capacity > 0 THEN
            v_energy_to_buy := LEAST(
                CEIL((v_energy_capacity - ai_player.energy) * 0.8),
                1000 -- Max per purchase
            );
            
            v_cost := v_energy_to_buy * v_port.price_energy;
            
            -- Use up to 20% of credits for energy if we have enough
            IF ai_player.credits >= v_cost AND ai_player.credits >= 1000 THEN
                UPDATE ships SET 
                    credits = credits - v_cost,
                    energy = energy + v_energy_to_buy
                WHERE id = ai_player.ship_id;
                v_success := TRUE;
            END IF;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;

-- Enhanced AI ship upgrade function with combat priorities
CREATE OR REPLACE FUNCTION "public"."ai_ship_upgrade"("p_ship_id" "uuid", "p_attr" "text") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_ship RECORD;
    v_cost BIGINT;
    v_success BOOLEAN := FALSE;
    v_priority INTEGER := 1;
BEGIN
    -- Get ship info
    SELECT * INTO v_ship FROM ships WHERE id = p_ship_id;
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    
    -- Calculate cost based on attribute and current level
    CASE p_attr
        WHEN 'engine' THEN 
            v_cost := 500 * (v_ship.engine_lvl + 1);
            v_priority := CASE 
                WHEN v_ship.engine_lvl < 5 THEN 8  -- High priority for low levels
                WHEN v_ship.engine_lvl < 10 THEN 6 -- Medium priority
                ELSE 4 END;
        WHEN 'computer' THEN 
            v_cost := 400 * (v_ship.comp_lvl + 1);
            v_priority := CASE 
                WHEN v_ship.comp_lvl < 8 THEN 9  -- Very high priority for fighters
                WHEN v_ship.comp_lvl < 15 THEN 7
                ELSE 5 END;
        WHEN 'sensors' THEN 
            v_cost := 400 * (v_ship.sensor_lvl + 1);
            v_priority := 3; -- Lower priority
        WHEN 'beam_weapons' THEN 
            v_cost := 1500 * (v_ship.beam_lvl + 1);
            v_priority := CASE 
                WHEN v_ship.beam_lvl < 5 THEN 7  -- High priority for combat
                WHEN v_ship.beam_lvl < 10 THEN 5
                ELSE 3 END;
        WHEN 'torpedo_launchers' THEN 
            v_cost := 2000 * (v_ship.torp_launcher_lvl + 1);
            v_priority := CASE 
                WHEN v_ship.torp_launcher_lvl < 5 THEN 8  -- Very high priority
                WHEN v_ship.torp_launcher_lvl < 10 THEN 6
                ELSE 4 END;
        WHEN 'armor' THEN 
            v_cost := 1000 * (v_ship.armor_lvl + 1);
            v_priority := CASE 
                WHEN v_ship.armor_lvl < 5 THEN 6  -- High priority for defense
                WHEN v_ship.armor_lvl < 10 THEN 4
                ELSE 2 END;
        WHEN 'power' THEN 
            v_cost := 750 * (v_ship.power_lvl + 1);
            v_priority := CASE 
                WHEN v_ship.power_lvl < 8 THEN 7  -- High priority for energy
                WHEN v_ship.power_lvl < 15 THEN 5
                ELSE 3 END;
        WHEN 'shields' THEN 
            v_cost := 1500 * (v_ship.shield_lvl + 1);
            v_priority := CASE 
                WHEN v_ship.shield_lvl < 5 THEN 6  -- High priority for defense
                WHEN v_ship.shield_lvl < 10 THEN 4
                ELSE 2 END;
        WHEN 'hull' THEN 
            v_cost := 2000 * (v_ship.hull_lvl + 1);
            v_priority := CASE 
                WHEN v_ship.hull_lvl < 5 THEN 5  -- Medium priority
                WHEN v_ship.hull_lvl < 10 THEN 3
                ELSE 1 END;
    END CASE;
    
    -- Check if ship has enough credits and priority is high enough
    IF v_ship.credits < v_cost THEN
        RETURN FALSE;
    END IF;
    
    -- Only upgrade if priority is high enough (combat-focused)
    IF v_priority < 4 THEN
        RETURN FALSE;
    END IF;

    -- Apply upgrade and deduct credits
    CASE p_attr
        WHEN 'engine' THEN 
            UPDATE ships SET engine_lvl = engine_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'computer' THEN 
            UPDATE ships SET comp_lvl = comp_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'sensors' THEN 
            UPDATE ships SET sensor_lvl = sensor_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'beam_weapons' THEN 
            UPDATE ships SET beam_lvl = beam_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'torpedo_launchers' THEN 
            UPDATE ships SET torp_launcher_lvl = torp_launcher_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'armor' THEN 
            UPDATE ships SET armor_lvl = armor_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'power' THEN 
            UPDATE ships SET power_lvl = power_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'shields' THEN 
            UPDATE ships SET shield_lvl = shield_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
        WHEN 'hull' THEN 
            UPDATE ships SET hull_lvl = hull_lvl + 1, credits = credits - v_cost WHERE id = p_ship_id;
    END CASE;

    v_success := TRUE;
    RETURN v_success;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;

-- Enhanced AI combat readiness function
CREATE OR REPLACE FUNCTION "public"."ai_combat_readiness"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_fighter_success BOOLEAN := FALSE;
    v_torpedo_success BOOLEAN := FALSE;
    v_energy_success BOOLEAN := FALSE;
BEGIN
    -- Try to buy fighters
    SELECT ai_buy_fighters(ai_player) INTO v_fighter_success;
    
    -- Try to buy torpedoes
    SELECT ai_buy_torpedoes(ai_player) INTO v_torpedo_success;
    
    -- Try to buy energy
    SELECT ai_buy_energy(ai_player) INTO v_energy_success;
    
    -- Return true if any combat purchase was successful
    v_success := v_fighter_success OR v_torpedo_success OR v_energy_success;
    
    RETURN v_success;
END;
$$;

-- Enhanced AI decision making with combat priorities
CREATE OR REPLACE FUNCTION "public"."ai_make_decision"("p_player_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_player_id uuid;
  v_player_handle text;
  v_sector_id uuid;
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
     WHERE w.from_sector_id = v_sector_id) as warps_count
  INTO v_planets_count, v_commodity_ports_count, v_special_ports_count, v_energy_ports_count, v_warps_count;
  
  -- Decision logic with combat-focused priorities
  v_decision := 'wait'; -- Default fallback
  
  -- Priority 1: No turns = wait
  IF v_turns <= 0 THEN
    v_decision := 'wait';
    
  -- Priority 2: Combat readiness at special ports (buy fighters/torpedoes)
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
    
  -- Priority 3: Energy buying at energy ports
  ELSIF v_energy_ports_count > 0 AND v_credits >= 1000 AND v_energy < (100 * POWER(1.5, v_power_lvl - 1) * 0.6)::INTEGER THEN
    v_decision := 'buy_energy';
    
  -- Priority 4: Claim planets (high value, limited opportunity)
  ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
    
  -- Priority 5: Trade at commodity ports (immediate profit)
  ELSIF v_commodity_ports_count > 0 AND v_credits >= 100 THEN
    v_decision := 'trade';
    
  -- Priority 6: Explore (only if we have warps to explore)
  ELSIF v_warps_count > 0 THEN
    v_decision := 'explore';
    
  -- Priority 7: Emergency actions
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

-- Enhanced AI execution function with new combat actions
CREATE OR REPLACE FUNCTION "public"."ai_execute_action"("ai_player" "record", "ai_memory" "record", "action" "text") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
    v_planet RECORD;
    v_target_sector RECORD;
    v_profit BIGINT;
    v_cost BIGINT;
BEGIN
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
