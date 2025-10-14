
\restrict nrJdW0riCvilLfd5zOJOfGY4RIelRJ3NtPzHNXOMMM9GqGwZMlAZBIKMWwYaUAT


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."ai_personality" AS ENUM (
    'trader',
    'explorer',
    'warrior',
    'colonizer',
    'balanced'
);


ALTER TYPE "public"."ai_personality" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_one_link_for_sector"("p_universe_name" "text", "p_sector_number" integer, "p_max_per_sector" integer DEFAULT 15) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_universe uuid;
  v_from uuid;
  v_to uuid;
  v_added boolean := false;
BEGIN
  SELECT id INTO v_universe FROM universes WHERE name = p_universe_name;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error','universe_not_found');
  END IF;

  SELECT id INTO v_from FROM sectors WHERE universe_id = v_universe AND number = p_sector_number;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error','sector_not_found');
  END IF;

  -- Find a partner sector under cap, not already linked (either direction)
  WITH deg AS (
    SELECT s.id AS sector_id,
           COALESCE((
             SELECT COUNT(*) FROM (
               SELECT DISTINCT CASE WHEN w.from_sector = s.id THEN w.to_sector ELSE w.from_sector END AS nbr
               FROM warps w
               WHERE w.universe_id = s.universe_id AND (w.from_sector = s.id OR w.to_sector = s.id)
             ) q
           ), 0) AS degree
    FROM sectors s
    WHERE s.universe_id = v_universe
  )
  SELECT d.sector_id INTO v_to
  FROM deg d
  WHERE d.sector_id <> v_from
    AND d.degree < p_max_per_sector
    AND NOT EXISTS (
      SELECT 1 FROM warps w
      WHERE w.universe_id = v_universe
        AND ((w.from_sector = v_from AND w.to_sector = d.sector_id) OR (w.from_sector = d.sector_id AND w.to_sector = v_from))
    )
  ORDER BY d.degree ASC, random()
  LIMIT 1;

  IF v_to IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'message','no_eligible_partner_found');
  END IF;

  BEGIN
    INSERT INTO warps (universe_id, from_sector, to_sector) VALUES (v_universe, v_from, v_to);
    INSERT INTO warps (universe_id, from_sector, to_sector) VALUES (v_universe, v_to, v_from);
    v_added := true;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;

  RETURN jsonb_build_object('ok', v_added, 'from', p_sector_number,
                             'to', (SELECT number FROM sectors WHERE id = v_to));
END;
$$;


ALTER FUNCTION "public"."add_one_link_for_sector"("p_universe_name" "text", "p_sector_number" integer, "p_max_per_sector" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_route_waypoint"("p_user_id" "uuid", "p_route_id" "uuid", "p_port_id" "uuid", "p_action_type" "text", "p_resource" "text" DEFAULT NULL::"text", "p_quantity" integer DEFAULT 0, "p_notes" "text" DEFAULT NULL::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_route RECORD;
    v_port RECORD;
    v_next_sequence INTEGER;
    v_result JSON;
BEGIN
    -- Verify route ownership
    SELECT tr.*, p.id as player_id
    INTO v_route
    FROM trade_routes tr
    JOIN players p ON tr.player_id = p.id
    WHERE tr.id = p_route_id AND p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'route_not_found', 'message', 'Route not found or access denied'));
    END IF;
    
    -- Verify port exists and is in the same universe
    SELECT p.*, s.universe_id
    INTO v_port
    FROM ports p
    JOIN sectors s ON p.sector_id = s.id
    WHERE p.id = p_port_id AND s.universe_id = v_route.universe_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'port_not_found', 'message', 'Port not found in this universe'));
    END IF;
    
    -- Validate action type and resource
    IF p_action_type NOT IN ('buy', 'sell', 'trade_auto') THEN
        RETURN json_build_object('error', json_build_object('code', 'invalid_action', 'message', 'Invalid action type'));
    END IF;
    
    IF p_action_type IN ('buy', 'sell') AND p_resource NOT IN ('ore', 'organics', 'goods', 'energy') THEN
        RETURN json_build_object('error', json_build_object('code', 'invalid_resource', 'message', 'Invalid resource type'));
    END IF;
    
    -- Get next sequence number
    SELECT COALESCE(MAX(sequence_order), 0) + 1
    INTO v_next_sequence
    FROM route_waypoints
    WHERE route_id = p_route_id;
    
    -- Add the waypoint
    INSERT INTO route_waypoints (route_id, sequence_order, port_id, action_type, resource, quantity, notes)
    VALUES (p_route_id, v_next_sequence, p_port_id, p_action_type, p_resource, p_quantity, p_notes);
    
    RETURN json_build_object(
        'ok', true,
        'waypoint_sequence', v_next_sequence,
        'message', 'Waypoint added successfully'
    );
END;
$$;


ALTER FUNCTION "public"."add_route_waypoint"("p_user_id" "uuid", "p_route_id" "uuid", "p_port_id" "uuid", "p_action_type" "text", "p_resource" "text", "p_quantity" integer, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_basic_action"("ai_player" "record", "action" "text") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_target_sector_id UUID;
    v_success BOOLEAN := FALSE;
BEGIN
    IF action = 'move_random' THEN
        SELECT id INTO v_target_sector_id
        FROM public.sectors
        WHERE universe_id = ai_player.universe_id AND id != ai_player.sector_id
        ORDER BY RANDOM()
        LIMIT 1;
        
        IF FOUND THEN
            UPDATE public.ships
            SET sector_id = v_target_sector_id
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_basic_action"("ai_player" "record", "action" "text") OWNER TO "postgres";


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
        -- Calculate fighter capacity
        v_fighter_capacity := (100 * POWER(1.5, ai_player.comp_lvl - 1))::INTEGER;
        
        -- Determine how many fighters to buy
        v_fighters_to_buy := LEAST(v_fighter_capacity - ai_player.fighters, 50);
        
        IF v_fighters_to_buy > 0 THEN
            v_cost := v_fighters_to_buy * 100; -- Assume 100 credits per fighter
            
            IF ai_player.credits >= v_cost THEN
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


ALTER FUNCTION "public"."ai_buy_fighters"("ai_player" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_claim_planet"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_planet RECORD;
    v_claim_cost BIGINT := 10000;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find unclaimed planet in current sector
    SELECT * INTO v_planet
    FROM planets
    WHERE sector_id = ai_player.sector_id 
    AND owner_player_id IS NULL
    ORDER BY RANDOM()
    LIMIT 1;
    
    IF FOUND AND ai_player.credits >= v_claim_cost THEN
        -- Claim the planet
        UPDATE planets
        SET owner_player_id = ai_player.id,
            colonists = 1000 + (RANDOM() * 500)::INTEGER,
            ore = 1000 + (RANDOM() * 2000)::INTEGER,
            organics = 1000 + (RANDOM() * 2000)::INTEGER,
            goods = 500 + (RANDOM() * 1000)::INTEGER,
            energy = 1500 + (RANDOM() * 1000)::INTEGER
        WHERE id = v_planet.id;
        
        -- Deduct cost
        UPDATE ships
        SET credits = credits - v_claim_cost
        WHERE id = ai_player.ship_id;
        
        -- Update AI memory
        UPDATE ai_player_memory 
        SET owned_planets = owned_planets + 1,
            current_goal = 'manage_planets'
        WHERE player_id = ai_player.id;
        
        v_success := TRUE;
    END IF;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_claim_planet"("ai_player" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_emergency_trade"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_port RECORD;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find any port in current sector
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id;
    
    IF FOUND THEN
        -- Sell any cargo we have for quick credits
        IF ai_player.ore > 0 THEN
            UPDATE ships SET 
                credits = credits + (v_port.price_ore * ai_player.ore)::BIGINT,
                ore = 0
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        IF ai_player.organics > 0 THEN
            UPDATE ships SET 
                credits = credits + (v_port.price_organics * ai_player.organics)::BIGINT,
                organics = 0
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        IF ai_player.goods > 0 THEN
            UPDATE ships SET 
                credits = credits + (v_port.price_goods * ai_player.goods)::BIGINT,
                goods = 0
            WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        -- If still low on credits, buy cheapest available commodity
        IF NOT v_success AND ai_player.credits >= 100 THEN
            IF v_port.ore > 0 AND v_port.price_ore <= ai_player.credits THEN
                UPDATE ships SET 
                    credits = credits - v_port.price_ore * 5,
                    ore = ore + 5
                WHERE id = ai_player.ship_id AND credits >= v_port.price_ore * 5;
                v_success := TRUE;
            END IF;
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_emergency_trade"("ai_player" "record") OWNER TO "postgres";


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
            v_success := public.ai_buy_fighters(ai_player);
            
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


ALTER FUNCTION "public"."ai_execute_action"("ai_player" "record", "ai_memory" "record", "action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_execute_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_result boolean := false;
  v_user_id uuid;
  v_sector_id uuid;
  v_sector_number int;
  v_port_id uuid;
  v_port_kind text;
  v_planet_id uuid;
  v_available_warps int[];
  v_target_sector int;
  v_action_result jsonb;
BEGIN
  -- Get player info with error handling
  SELECT user_id, current_sector 
  INTO v_user_id, v_sector_id
  FROM public.players 
  WHERE id = p_player_id AND is_ai = true;
  
  IF v_user_id IS NULL OR v_sector_id IS NULL THEN
    RETURN false;
  END IF;
  
  -- Get current sector number
  SELECT number INTO v_sector_number
  FROM public.sectors
  WHERE id = v_sector_id;
  
  IF v_sector_number IS NULL THEN
    RETURN false;
  END IF;
  
  -- Execute action based on decision
  CASE p_action
    WHEN 'claim_planet' THEN
      -- Find first unclaimed planet in current sector
      SELECT id INTO v_planet_id
      FROM public.planets
      WHERE sector_id = v_sector_id 
        AND owner_player_id IS NULL
      LIMIT 1;
      
      IF v_planet_id IS NOT NULL THEN
        BEGIN
          SELECT public.game_planet_claim(v_user_id, v_sector_number, 'AI Colony', p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    WHEN 'trade' THEN
      -- Find commodity port (not special port)
      SELECT id, kind 
      INTO v_port_id, v_port_kind
      FROM public.ports
      WHERE sector_id = v_sector_id 
        AND kind IN ('ore', 'organics', 'goods', 'energy')
      LIMIT 1;
      
      IF v_port_id IS NOT NULL THEN
        BEGIN
          -- Try to buy ore (simple trade)
          SELECT public.game_trade(v_user_id, v_port_id, 'buy', 'ore', 1, p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    WHEN 'upgrade_ship' THEN
      -- Find special port
      SELECT id 
      INTO v_port_id
      FROM public.ports
      WHERE sector_id = v_sector_id 
        AND kind = 'special'
      LIMIT 1;
      
      IF v_port_id IS NOT NULL THEN
        BEGIN
          -- Try to upgrade hull
          SELECT public.game_ship_upgrade(v_user_id, 'hull', p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    WHEN 'explore' THEN
      -- Get available warps from current sector
      SELECT ARRAY_AGG(s.number)
      INTO v_available_warps
      FROM public.warps w
      JOIN public.sectors s ON s.id = w.to_sector_id
      WHERE w.from_sector_id = v_sector_id;
      
      IF v_available_warps IS NOT NULL AND array_length(v_available_warps, 1) > 0 THEN
        -- Pick random connected sector
        v_target_sector := v_available_warps[1 + floor(random() * array_length(v_available_warps, 1))::int];
        
        BEGIN
          SELECT public.game_move(v_user_id, v_target_sector, p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    WHEN 'emergency_trade' THEN
      -- Try to sell any cargo for credits
      SELECT id 
      INTO v_port_id
      FROM public.ports
      WHERE sector_id = v_sector_id 
        AND kind IN ('ore', 'organics', 'goods', 'energy')
      LIMIT 1;
      
      IF v_port_id IS NOT NULL THEN
        BEGIN
          -- Try to sell ore
          SELECT public.game_trade(v_user_id, v_port_id, 'sell', 'ore', 1, p_universe_id) 
          INTO v_action_result;
          v_result := COALESCE((v_action_result->>'success')::boolean, false);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    ELSE
      v_result := false;
  END CASE;
  
  RETURN v_result;
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;


ALTER FUNCTION "public"."ai_execute_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_execute_real_action"("ai_player" "record", "ai_memory" "record", "action" "text") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_target_sector_id UUID;
    v_planet_id UUID;
    v_result JSONB;
    v_ports_in_sector INTEGER;
    v_unclaimed_planets INTEGER;
    v_credits_needed BIGINT;
BEGIN
    -- Check current sector status
    SELECT COUNT(*) INTO v_ports_in_sector FROM ports WHERE sector_id = ai_player.sector_id;
    SELECT COUNT(*) INTO v_unclaimed_planets FROM planets p WHERE p.sector_id = ai_player.sector_id AND p.owner_player_id IS NULL;
    
    CASE action
        WHEN 'claim_planet' THEN
            -- Only try to claim if there are unclaimed planets
            IF v_unclaimed_planets > 0 THEN
                SELECT id INTO v_planet_id
                FROM planets p
                WHERE p.sector_id = ai_player.sector_id AND p.owner_player_id IS NULL
                LIMIT 1;
                
                IF FOUND THEN
                    SELECT public.game_planet_claim(ai_player.id, v_planet_id) INTO v_result;
                    v_success := (v_result->>'success')::BOOLEAN;
                END IF;
            END IF;
            
        WHEN 'trade_at_port' THEN
            -- Only try to trade if there are ports in the sector
            IF v_ports_in_sector > 0 THEN
                -- Try to sell cargo if we have any
                IF ai_player.ore > 0 OR ai_player.organics > 0 OR ai_player.goods > 0 THEN
                    -- Use existing trade function (simplified - just sell ore for now)
                    IF ai_player.ore > 0 THEN
                        SELECT public.game_trade(ai_player.id, 'ore', ai_player.ore, 'sell') INTO v_result;
                        v_success := (v_result->>'success')::BOOLEAN;
                    END IF;
                END IF;
            END IF;
            
        WHEN 'upgrade_ship' THEN
            -- Try to upgrade the cheapest available upgrade
            IF ai_player.hull_lvl < 10 THEN
                v_credits_needed := 1000 * POWER(2, ai_player.hull_lvl);
                IF ai_player.credits >= v_credits_needed THEN
                    SELECT public.game_ship_upgrade(ai_player.id, ai_player.ship_id, 'hull') INTO v_result;
                    v_success := (v_result->>'success')::BOOLEAN;
                END IF;
            ELSIF ai_player.engine_lvl < 10 THEN
                v_credits_needed := 1000 * POWER(2, ai_player.engine_lvl);
                IF ai_player.credits >= v_credits_needed THEN
                    SELECT public.game_ship_upgrade(ai_player.id, ai_player.ship_id, 'engine') INTO v_result;
                    v_success := (v_result->>'success')::BOOLEAN;
                END IF;
            END IF;
            
        WHEN 'explore_sectors' THEN
            -- Move to a random sector to explore
            SELECT s.id INTO v_target_sector_id
            FROM sectors s
            WHERE s.universe_id = ai_player.universe_id 
            AND s.id != ai_player.sector_id
            ORDER BY RANDOM()
            LIMIT 1;
            
            IF FOUND THEN
                SELECT public.game_move(ai_player.id, v_target_sector_id) INTO v_result;
                v_success := (v_result->>'success')::BOOLEAN;
            END IF;
            
        ELSE
            -- Default: explore (move to random sector)
            SELECT s.id INTO v_target_sector_id
            FROM sectors s
            WHERE s.universe_id = ai_player.universe_id 
            AND s.id != ai_player.sector_id
            ORDER BY RANDOM()
            LIMIT 1;
            
            IF FOUND THEN
                SELECT public.game_move(ai_player.id, v_target_sector_id) INTO v_result;
                v_success := (v_result->>'success')::BOOLEAN;
            END IF;
    END CASE;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_execute_real_action"("ai_player" "record", "ai_memory" "record", "action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_universe_id uuid;
BEGIN
  SELECT universe_id INTO v_universe_id
  FROM public.players
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_universe_id IS NULL THEN
    RETURN jsonb_build_object('error', 'universe_not_found_for_user');
  END IF;

  RETURN public.ai_hyperspace(p_user_id, p_target_sector_number, v_universe_id);
END;
$$;


ALTER FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  SELECT public.game_hyperspace(p_user_id, p_target_sector_number, p_universe_id);
$$;


ALTER FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid") OWNER TO "postgres";


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
  v_planets_count int := 0;
  v_commodity_ports_count int := 0;
  v_special_ports_count int := 0;
  v_warps_count int := 0;
  v_decision text;
  v_decision_weight int;
BEGIN
  -- Get comprehensive player and ship info
  SELECT p.id, p.handle, p.current_sector, p.turns, p.is_ai,
         s.credits, s.hull, s.hull_max, s.armor_lvl, s.energy, s.fighters, s.torpedoes
  INTO v_player_id, v_player_handle, v_sector_id, v_turns, v_is_ai, v_credits, v_hull_level, v_hull_max, v_armor_lvl, v_energy, v_fighters, v_torpedoes
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
     WHERE pr.sector_id = v_sector_id AND pr.kind IN ('ore', 'organics', 'goods', 'energy')) as commodity_ports,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind = 'special') as special_ports,
    (SELECT COUNT(*) FROM public.warps w 
     WHERE w.from_sector_id = v_sector_id) as warps_count
  INTO v_planets_count, v_commodity_ports_count, v_special_ports_count, v_warps_count;
  
  -- Decision logic with weighted priorities
  v_decision := 'wait'; -- Default fallback
  
  -- Priority 1: No turns = wait
  IF v_turns <= 0 THEN
    v_decision := 'wait';
    
  -- Priority 2: Claim planets (high value, limited opportunity)
  ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
    
  -- Priority 3: Trade at commodity ports (immediate profit)
  ELSIF v_commodity_ports_count > 0 AND v_credits >= 100 THEN
    v_decision := 'trade';
    
  -- Priority 4: Upgrade ship at special ports (long-term benefit)
  ELSIF v_special_ports_count > 0 AND v_credits >= 500 AND v_hull_level < 5 THEN
    v_decision := 'upgrade_ship';
    
  -- Priority 5: Explore (only if we have warps to explore)
  ELSIF v_warps_count > 0 THEN
    v_decision := 'explore';
    
  -- Priority 6: Emergency actions
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


ALTER FUNCTION "public"."ai_make_decision"("p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_make_decision"("ai_player" "record", "ai_memory" "record") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_decision TEXT := 'explore';
    v_credits_threshold BIGINT;
    v_random_factor FLOAT := RANDOM();
BEGIN
    -- Set thresholds based on personality
    CASE ai_player.ai_personality
        WHEN 'trader' THEN v_credits_threshold := 5000;
        WHEN 'explorer' THEN v_credits_threshold := 15000;
        WHEN 'warrior' THEN v_credits_threshold := 8000;
        WHEN 'colonizer' THEN v_credits_threshold := 12000;
        ELSE v_credits_threshold := 10000; -- balanced
    END CASE;
    
    -- Decision tree based on personality and current state
    IF ai_player.ai_personality = 'trader' THEN
        -- Traders prioritize profitable trading
        IF ai_player.credits < 2000 THEN
            v_decision := 'emergency_trade';
        ELSIF v_random_factor < 0.7 THEN
            v_decision := 'optimize_trade';
        ELSIF ai_player.credits > 20000 AND v_random_factor < 0.9 THEN
            v_decision := 'upgrade_ship';
        ELSE
            v_decision := 'explore_markets';
        END IF;
        
    ELSIF ai_player.ai_personality = 'explorer' THEN
        -- Explorers prioritize movement and discovery
        IF ai_player.credits < 5000 THEN
            v_decision := 'trade_for_funds';
        ELSIF v_random_factor < 0.6 THEN
            v_decision := 'strategic_explore';
        ELSIF v_random_factor < 0.8 THEN
            v_decision := 'claim_planet';
        ELSE
            v_decision := 'upgrade_engines';
        END IF;
        
    ELSIF ai_player.ai_personality = 'warrior' THEN
        -- Warriors prioritize combat readiness and aggression
        IF ai_player.credits < 3000 THEN
            v_decision := 'raid_trade';
        ELSIF ai_player.fighters < 50 AND ai_player.credits > 10000 THEN
            v_decision := 'buy_fighters';
        ELSIF v_random_factor < 0.5 THEN
            v_decision := 'upgrade_weapons';
        ELSIF v_random_factor < 0.8 THEN
            v_decision := 'patrol_territory';
        ELSE
            v_decision := 'strategic_move';
        END IF;
        
    ELSIF ai_player.ai_personality = 'colonizer' THEN
        -- Colonizers prioritize planet acquisition and management
        IF ai_player.credits < 8000 THEN
            v_decision := 'resource_gather';
        ELSIF v_random_factor < 0.6 THEN
            v_decision := 'claim_planet';
        ELSIF v_random_factor < 0.8 THEN
            v_decision := 'manage_planets';
        ELSE
            v_decision := 'expand_territory';
        END IF;
        
    ELSE -- balanced personality
        -- Balanced approach to all activities
        IF ai_player.credits < 5000 THEN
            v_decision := 'basic_trade';
        ELSIF v_random_factor < 0.3 THEN
            v_decision := 'trade_goods';
        ELSIF v_random_factor < 0.5 THEN
            v_decision := 'claim_planet';
        ELSIF v_random_factor < 0.7 THEN
            v_decision := 'upgrade_ship';
        ELSIF v_random_factor < 0.9 THEN
            v_decision := 'strategic_move';
        ELSE
            v_decision := 'explore';
        END IF;
    END IF;
    
    RETURN v_decision;
END;
$$;


ALTER FUNCTION "public"."ai_make_decision"("ai_player" "record", "ai_memory" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_make_decision_debug"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS "text"
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
  v_planets_count int := 0;
  v_commodity_ports_count int := 0;
  v_special_ports_count int := 0;
  v_warps_count int := 0;
  v_decision text;
  v_debug_data jsonb;
BEGIN
  -- Log start of decision process
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_start', 
    jsonb_build_object('player_id', p_player_id));
  
  -- Get comprehensive player and ship info
  SELECT p.id, p.handle, p.current_sector, p.turns, p.is_ai,
         s.credits, s.hull, s.hull_max, s.armor_lvl, s.energy, s.fighters, s.torpedoes
  INTO v_player_id, v_player_handle, v_sector_id, v_turns, v_is_ai, v_credits, v_hull_level, v_hull_max, v_armor_lvl, v_energy, v_fighters, v_torpedoes
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.is_ai = true;
  
  IF NOT FOUND THEN
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'player_not_found', 
      jsonb_build_object('player_id', p_player_id));
    RETURN 'wait';
  END IF;
  
  v_turns := COALESCE(v_turns, 0);
  
  -- Log player data
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'player_data', 
    jsonb_build_object(
      'handle', v_player_handle,
      'turns', v_turns,
      'credits', v_credits,
      'hull', v_hull_level,
      'sector_id', v_sector_id
    ));
  
  -- Get comprehensive sector information
  SELECT 
    (SELECT COUNT(*) FROM public.planets pl 
     WHERE pl.sector_id = v_sector_id AND pl.owner_player_id IS NULL) as unclaimed_planets,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind IN ('ore', 'organics', 'goods', 'energy')) as commodity_ports,
    (SELECT COUNT(*) FROM public.ports pr 
     WHERE pr.sector_id = v_sector_id AND pr.kind = 'special') as special_ports,
    (SELECT COUNT(*) FROM public.warps w 
     WHERE w.from_sector_id = v_sector_id) as warps_count
  INTO v_planets_count, v_commodity_ports_count, v_special_ports_count, v_warps_count;
  
  -- Log sector data
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'sector_data', 
    jsonb_build_object(
      'planets_count', v_planets_count,
      'commodity_ports_count', v_commodity_ports_count,
      'special_ports_count', v_special_ports_count,
      'warps_count', v_warps_count
    ));
  
  -- Decision logic with weighted priorities
  v_decision := 'wait'; -- Default fallback
  
  -- Priority 1: No turns = wait
  IF v_turns <= 0 THEN
    v_decision := 'wait';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_no_turns', 
      jsonb_build_object('turns', v_turns));
    
  -- Priority 2: Claim planets (high value, limited opportunity)
  ELSIF v_planets_count > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_claim_planet', 
      jsonb_build_object('planets_count', v_planets_count, 'credits', v_credits));
    
  -- Priority 3: Trade at commodity ports (immediate profit)
  ELSIF v_commodity_ports_count > 0 AND v_credits >= 100 THEN
    v_decision := 'trade';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_trade', 
      jsonb_build_object('commodity_ports_count', v_commodity_ports_count, 'credits', v_credits));
    
  -- Priority 4: Upgrade ship at special ports (long-term benefit)
  ELSIF v_special_ports_count > 0 AND v_credits >= 500 AND v_hull_level < 5 THEN
    v_decision := 'upgrade_ship';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_upgrade', 
      jsonb_build_object('special_ports_count', v_special_ports_count, 'credits', v_credits, 'hull', v_hull_level));
    
  -- Priority 5: Explore (only if we have warps to explore)
  ELSIF v_warps_count > 0 THEN
    v_decision := 'explore';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_explore', 
      jsonb_build_object('warps_count', v_warps_count));
    
  -- Priority 6: Emergency actions
  ELSIF v_credits < 100 THEN
    v_decision := 'emergency_trade';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_emergency', 
      jsonb_build_object('credits', v_credits));
    
  ELSE
    -- Fallback: wait for better opportunities
    v_decision := 'wait';
    PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_wait_fallback', 
      jsonb_build_object('reason', 'no_suitable_actions'));
  END IF;
  
  -- Log final decision
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_final', 
    jsonb_build_object('decision', v_decision));
  
  RETURN v_decision;
EXCEPTION WHEN OTHERS THEN
  PERFORM log_ai_debug(p_player_id, p_universe_id, 'decision_error', 
    jsonb_build_object('error', SQLERRM));
  RETURN 'wait';
END;
$$;


ALTER FUNCTION "public"."ai_make_decision_debug"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_make_simple_decision"("ai_player" "record", "ai_memory" "record") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_ports_in_sector INTEGER;
    v_unclaimed_planets INTEGER;
    v_has_cargo BOOLEAN;
    v_can_afford_upgrade BOOLEAN;
    v_random NUMERIC := RANDOM();
BEGIN
    -- Check current sector status
    SELECT COUNT(*) INTO v_ports_in_sector FROM ports WHERE sector_id = ai_player.sector_id;
    SELECT COUNT(*) INTO v_unclaimed_planets FROM planets p WHERE p.sector_id = ai_player.sector_id AND p.owner_player_id IS NULL;
    
    -- Check player status
    v_has_cargo := (ai_player.ore > 0 OR ai_player.organics > 0 OR ai_player.goods > 0);
    v_can_afford_upgrade := (ai_player.credits >= 1000 * POWER(2, ai_player.hull_lvl));
    
    -- Simple decision tree based on current situation
    IF v_unclaimed_planets > 0 AND ai_player.credits >= 10000 THEN
        RETURN 'claim_planet';
    ELSIF v_ports_in_sector > 0 AND v_has_cargo THEN
        RETURN 'trade_at_port';
    ELSIF v_can_afford_upgrade THEN
        RETURN 'upgrade_ship';
    ELSE
        RETURN 'explore_sectors';
    END IF;
END;
$$;


ALTER FUNCTION "public"."ai_make_simple_decision"("ai_player" "record", "ai_memory" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_manage_planets"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_planet RECORD;
    v_success BOOLEAN := FALSE;
    v_transfer_amount INTEGER;
BEGIN
    -- Find our planets and optimize their production
    FOR v_planet IN
        SELECT * FROM planets 
        WHERE owner_player_id = ai_player.id
        ORDER BY RANDOM()
        LIMIT 3
    LOOP
        -- Transfer resources between ship and planet strategically
        
        -- If planet needs colonists and we have some
        IF v_planet.colonists < 5000 AND ai_player.colonists > 100 THEN
            v_transfer_amount := LEAST(ai_player.colonists, 1000);
            
            UPDATE planets SET colonists = colonists + v_transfer_amount WHERE id = v_planet.id;
            UPDATE ships SET colonists = colonists - v_transfer_amount WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
        
        -- If we need cargo space and planet has excess resources
        IF ai_player.ore + ai_player.organics + ai_player.goods < 500 THEN
            IF v_planet.ore > 3000 THEN
                v_transfer_amount := 1000;
                UPDATE planets SET ore = ore - v_transfer_amount WHERE id = v_planet.id;
                UPDATE ships SET ore = ore + v_transfer_amount WHERE id = ai_player.ship_id;
                v_success := TRUE;
            ELSIF v_planet.organics > 3000 THEN
                v_transfer_amount := 1000;
                UPDATE planets SET organics = organics - v_transfer_amount WHERE id = v_planet.id;
                UPDATE ships SET organics = organics + v_transfer_amount WHERE id = ai_player.ship_id;
                v_success := TRUE;
            END IF;
        END IF;
        
        -- Store excess ship cargo on planets
        IF ai_player.ore > 1000 THEN
            UPDATE planets SET ore = ore + ai_player.ore WHERE id = v_planet.id;
            UPDATE ships SET ore = 0 WHERE id = ai_player.ship_id;
            v_success := TRUE;
        END IF;
    END LOOP;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_manage_planets"("ai_player" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_optimize_trading"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_port RECORD;
    v_best_profit BIGINT := 0;
    v_best_trade_action TEXT := NULL;
    v_best_commodity TEXT := NULL;
    v_quantity INTEGER := 0;
    v_cargo_space INTEGER;
    v_current_cargo INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Get current ship cargo and capacity
    SELECT 
        COALESCE(ore, 0) + COALESCE(organics, 0) + COALESCE(goods, 0) + COALESCE(energy, 0) + COALESCE(colonists, 0)
    INTO v_current_cargo
    FROM ships WHERE id = ai_player.ship_id;

    SELECT hull_max INTO v_cargo_space FROM ships WHERE id = ai_player.ship_id;

    -- Find ports in the current sector
    FOR v_port IN SELECT * FROM ports WHERE sector_id = ai_player.sector_id
    LOOP
        -- Evaluate selling opportunities
        IF ai_player.ore > 0 AND v_port.kind != 'ore' AND v_port.buy_ore THEN
            IF v_port.price_ore * ai_player.ore > v_best_profit THEN
                v_best_profit := v_port.price_ore * ai_player.ore;
                v_best_trade_action := 'sell';
                v_best_commodity := 'ore';
                v_quantity := ai_player.ore;
            END IF;
        END IF;
        
        -- Similar logic for organics
        IF ai_player.organics > 0 AND v_port.kind != 'organics' AND v_port.buy_organics THEN
            IF v_port.price_organics * ai_player.organics > v_best_profit THEN
                v_best_profit := v_port.price_organics * ai_player.organics;
                v_best_trade_action := 'sell';
                v_best_commodity := 'organics';
                v_quantity := ai_player.organics;
            END IF;
        END IF;
        
        -- Similar logic for goods
        IF ai_player.goods > 0 AND v_port.kind != 'goods' AND v_port.buy_goods THEN
            IF v_port.price_goods * ai_player.goods > v_best_profit THEN
                v_best_profit := v_port.price_goods * ai_player.goods;
                v_best_trade_action := 'sell';
                v_best_commodity := 'goods';
                v_quantity := ai_player.goods;
            END IF;
        END IF;

        -- Evaluate buying opportunities if we have cargo space and credits
        IF v_cargo_space - v_current_cargo > 0 AND ai_player.credits > 1000 THEN
            -- Buy ore if profitable
            IF v_port.kind = 'ore' AND v_port.sell_ore AND v_port.stock_ore > 0 THEN
                IF ai_player.credits >= v_port.price_ore * 10 AND v_port.stock_ore >= 10 THEN
                    IF v_best_profit = 0 THEN -- If no selling opportunity, consider buying
                        v_best_profit := 1;
                        v_best_trade_action := 'buy';
                        v_best_commodity := 'ore';
                        v_quantity := LEAST(10, v_cargo_space - v_current_cargo, v_port.stock_ore);
                    END IF;
                END IF;
            END IF;
            
            -- Similar logic for other commodities...
        END IF;
    END LOOP;

    -- Execute the best trade action
    IF v_best_trade_action = 'sell' THEN
        CASE v_best_commodity
            WHEN 'ore' THEN
                UPDATE ships SET credits = credits + (v_port.price_ore * v_quantity), ore = ore - v_quantity WHERE id = ai_player.ship_id;
            WHEN 'organics' THEN
                UPDATE ships SET credits = credits + (v_port.price_organics * v_quantity), organics = organics - v_quantity WHERE id = ai_player.ship_id;
            WHEN 'goods' THEN
                UPDATE ships SET credits = credits + (v_port.price_goods * v_quantity), goods = goods - v_quantity WHERE id = ai_player.ship_id;
        END CASE;
        v_success := TRUE;
        
    ELSIF v_best_trade_action = 'buy' THEN
        CASE v_best_commodity
            WHEN 'ore' THEN
                UPDATE ships SET credits = credits - (v_port.price_ore * v_quantity), ore = ore + v_quantity WHERE id = ai_player.ship_id;
        END CASE;
        v_success := TRUE;
    END IF;

    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_optimize_trading"("ai_player" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_patrol_territory"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_target_sector RECORD;
    v_owned_planets INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find sectors with our planets to patrol
    SELECT s.id, s.number, COUNT(p.id) as planet_count
    INTO v_target_sector
    FROM sectors s
    JOIN planets p ON p.sector_id = s.id
    WHERE p.owner_player_id = ai_player.id
    AND s.id != ai_player.sector_id
    GROUP BY s.id, s.number
    ORDER BY RANDOM()
    LIMIT 1;
    
    IF FOUND THEN
        -- Move to patrol that sector
        UPDATE ships SET sector_id = v_target_sector.id WHERE id = ai_player.ship_id;
        v_success := TRUE;
    ELSE
        -- No owned planets to patrol, do strategic movement
        v_success := public.ai_strategic_move(ai_player);
    END IF;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_patrol_territory"("ai_player" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_ship_upgrade"("p_ship_id" "uuid", "p_attr" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_ship RECORD;
    v_cost INTEGER;
    v_current_level INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Get ship info
    SELECT s.*, p.current_sector INTO v_ship 
    FROM ships s
    JOIN players p ON s.player_id = p.id
    WHERE s.id = p_ship_id;
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Check if ship is at a Special port
    IF NOT EXISTS (
        SELECT 1 FROM ports p 
        JOIN sectors s ON p.sector_id = s.id 
        WHERE s.id = v_ship.current_sector AND p.kind = 'special'
    ) THEN
        RETURN FALSE;
    END IF;

    -- Get current level and calculate cost
    CASE p_attr
        WHEN 'engine' THEN 
            v_current_level := v_ship.engine_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'computer' THEN 
            v_current_level := v_ship.comp_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'sensors' THEN 
            v_current_level := v_ship.sensor_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'beam_weapons' THEN 
            v_current_level := v_ship.beam_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'torpedo_launchers' THEN 
            v_current_level := v_ship.torp_launcher_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'armor' THEN 
            v_current_level := v_ship.armor_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        WHEN 'power' THEN 
            v_current_level := v_ship.power_lvl;
            v_cost := 1000 * POWER(2, v_current_level);
        ELSE
            RETURN FALSE;
    END CASE;

    -- Check if ship has enough credits
    IF v_ship.credits < v_cost THEN
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
    END CASE;

    v_success := TRUE;
    RETURN v_success;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;


ALTER FUNCTION "public"."ai_ship_upgrade"("p_ship_id" "uuid", "p_attr" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_strategic_explore"("ai_player" "record", "ai_memory" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_target_sector RECORD;
    v_best_sector RECORD;
    v_best_score INTEGER := -1;
    v_current_score INTEGER;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find strategic sectors to explore (those with ports, planets, or other players)
    FOR v_target_sector IN
        SELECT s.id, s.number, s.universe_id,
               (SELECT COUNT(*) FROM ports p WHERE p.sector_id = s.id) as port_count,
               (SELECT COUNT(*) FROM planets pl WHERE pl.sector_id = s.id AND pl.owner_player_id IS NULL) as unclaimed_planets,
               (SELECT COUNT(*) FROM ships sh JOIN players p ON sh.player_id = p.id 
                WHERE sh.sector_id = s.id AND p.is_ai = FALSE) as human_players
        FROM sectors s
        WHERE s.universe_id = ai_player.universe_id 
        AND s.id != ai_player.sector_id
        ORDER BY RANDOM()
        LIMIT 10
    LOOP
        -- Calculate exploration score
        v_current_score := v_target_sector.port_count * 3 + 
                          v_target_sector.unclaimed_planets * 5 + 
                          v_target_sector.human_players * 2;
        
        -- Bonus for sectors we haven't visited recently
        IF ai_memory.exploration_targets IS NULL OR 
           NOT (ai_memory.exploration_targets ? v_target_sector.id::TEXT) THEN
            v_current_score := v_current_score + 10;
        END IF;
        
        IF v_current_score > v_best_score THEN
            v_best_score := v_current_score;
            v_best_sector := v_target_sector;
        END IF;
    END LOOP;
    
    -- Move to the best sector
    IF v_best_sector.id IS NOT NULL THEN
        UPDATE ships SET sector_id = v_best_sector.id WHERE id = ai_player.ship_id;
        
        -- Update exploration memory
        UPDATE ai_player_memory 
        SET exploration_targets = COALESCE(exploration_targets, '[]'::jsonb) || 
                                 jsonb_build_object(v_best_sector.id::TEXT, NOW()::TEXT),
            target_sector_id = v_best_sector.id
        WHERE player_id = ai_player.id;
        
        v_success := TRUE;
    END IF;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_strategic_explore"("ai_player" "record", "ai_memory" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_strategic_move"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_target_sector RECORD;
    v_move_score INTEGER;
    v_best_score INTEGER := -1;
    v_best_sector RECORD;
    v_success BOOLEAN := FALSE;
BEGIN
    -- Find strategic sectors to move to
    FOR v_target_sector IN
        SELECT s.id, s.number,
               (SELECT COUNT(*) FROM ports p WHERE p.sector_id = s.id) as port_count,
               (SELECT COUNT(*) FROM planets pl WHERE pl.sector_id = s.id AND pl.owner_player_id IS NULL) as free_planets,
               (SELECT COUNT(*) FROM ships sh JOIN players pl ON sh.player_id = pl.id 
                WHERE sh.sector_id = s.id AND pl.is_ai = FALSE) as human_count,
               (SELECT COUNT(*) FROM ships sh JOIN players pl ON sh.player_id = pl.id 
                WHERE sh.sector_id = s.id AND pl.is_ai = TRUE AND pl.id != ai_player.id) as ai_count
        FROM sectors s
        WHERE s.universe_id = ai_player.universe_id
        AND s.id != ai_player.sector_id
        ORDER BY RANDOM()
        LIMIT 15
    LOOP
        -- Calculate movement score based on personality
        v_move_score := 0;
        
        CASE ai_player.ai_personality
            WHEN 'trader' THEN
                v_move_score := v_target_sector.port_count * 5 + v_target_sector.human_count * 3;
                
            WHEN 'explorer' THEN
                v_move_score := v_target_sector.free_planets * 4 + (15 - v_target_sector.ai_count - v_target_sector.human_count) * 2;
                
            WHEN 'warrior' THEN
                v_move_score := v_target_sector.human_count * 6 + v_target_sector.ai_count * 3 + v_target_sector.port_count * 2;
                
            WHEN 'colonizer' THEN
                v_move_score := v_target_sector.free_planets * 8 + v_target_sector.port_count * 2;
                
            ELSE -- balanced
                v_move_score := v_target_sector.port_count * 2 + v_target_sector.free_planets * 3 + v_target_sector.human_count * 1;
        END CASE;
        
        -- Add randomness
        v_move_score := v_move_score + (RANDOM() * 5)::INTEGER;
        
        IF v_move_score > v_best_score THEN
            v_best_score := v_move_score;
            v_best_sector := v_target_sector;
        END IF;
    END LOOP;
    
    -- Move to best sector
    IF v_best_sector.id IS NOT NULL THEN
        UPDATE ships SET sector_id = v_best_sector.id WHERE id = ai_player.ship_id;
        v_success := TRUE;
    END IF;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_strategic_move"("ai_player" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_upgrade_engines"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
BEGIN
    -- Check if at Special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- Upgrade engines for exploration
        IF ai_player.engine_lvl < 15 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'engine');
        ELSIF ai_player.sensor_lvl < 10 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'sensors');
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_upgrade_engines"("ai_player" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_upgrade_ship"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
BEGIN
    -- Check if at Special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- General upgrades based on current levels
        IF ai_player.hull_lvl < 10 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'hull');
        ELSIF ai_player.power_lvl < 8 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'power');
        ELSIF ai_player.comp_lvl < 8 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'computer');
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_upgrade_ship"("ai_player" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_upgrade_weapons"("ai_player" "record") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
BEGIN
    -- Check if at Special port
    SELECT * INTO v_port FROM ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
    
    IF FOUND THEN
        -- Prioritize weapon upgrades for warriors
        IF ai_player.beam_lvl < 10 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'beam_weapons');
        ELSIF ai_player.torp_launcher_lvl < 8 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'torpedo_launchers');
        ELSIF ai_player.armor_lvl < 8 THEN
            v_success := public.ai_ship_upgrade(ai_player.ship_id, 'armor');
        END IF;
    END IF;
    
    RETURN v_success;
END;
$$;


ALTER FUNCTION "public"."ai_upgrade_weapons"("ai_player" "record") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_federation_rules"("p_universe_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Set Federation sectors (0-10) as safe zones
  UPDATE public.sectors
  SET 
    allow_attacking = false,
    allow_planet_creation = 'no',
    allow_sector_defense = 'no',
    name = 'Federation Territory'
  WHERE universe_id = p_universe_id 
    AND number BETWEEN 0 AND 10;
    
  RAISE NOTICE 'Applied Federation rules to sectors 0-10 in universe %', p_universe_id;
END;
$$;


ALTER FUNCTION "public"."apply_federation_rules"("p_universe_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."apply_federation_rules"("p_universe_id" "uuid") IS 'Applies Federation safe zone rules to sectors 0-10 in a universe';



CREATE OR REPLACE FUNCTION "public"."apply_igb_interest"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- TODO: Implement IGB interest calculation
    -- This should calculate and apply interest to IGB accounts
    
    RETURN jsonb_build_object(
        'message', 'IGB interest placeholder - not yet implemented',
        'universe_id', p_universe_id,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."apply_igb_interest"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_trade"("p_user_id" "uuid", "p_port_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player players;
  v_ship ships;
  v_port ports;
  v_sector sectors;
  pc text;
  native_price numeric;
  sell_price numeric;
  proceeds numeric;
  total_proceeds numeric := 0;
  trade_summary jsonb := '[]'::jsonb;
  trade_item jsonb;
  err jsonb;
BEGIN
  -- Load player, ship, port with universe validation
  SELECT * INTO v_player FROM players WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Player not found')); END IF;

  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Ship not found')); END IF;

  SELECT p.* INTO v_port
  FROM public.ports p
  WHERE p.id = p_port FOR UPDATE;
  
  SELECT s.number as sector_number, s.universe_id INTO v_sector
  FROM public.sectors s
  JOIN public.ports p ON s.id = p.sector_id
  WHERE p.id = p_port;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Port not found')); END IF;
  IF v_port.kind = 'special' THEN RETURN jsonb_build_object('error', jsonb_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.')); END IF;

  -- Universe validation
  IF v_player.universe_id != v_sector.universe_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_mismatch', 'message', 'Port not in player universe'));
  END IF;

  -- Validate co-location
  IF v_player.current_sector <> v_port.sector_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code','wrong_sector','message','Player not in port sector'));
  END IF;

  pc := v_port.kind; -- ore|organics|goods|energy

  -- Enhanced pricing with dynamic stock-based multipliers
  native_price := CASE pc
    WHEN 'ore' THEN v_port.price_ore * calculate_price_multiplier(v_port.ore, v_port.kind)
    WHEN 'organics' THEN v_port.price_organics * calculate_price_multiplier(v_port.organics, v_port.kind)
    WHEN 'goods' THEN v_port.price_goods * calculate_price_multiplier(v_port.goods, v_port.kind)
    WHEN 'energy' THEN v_port.price_energy * calculate_price_multiplier(v_port.energy, v_port.kind)
  END;
  sell_price := native_price * 0.90; -- player buys from port at 0.90 * dynamic price

  -- Compute proceeds from selling all non-native at 1.10 * dynamic price
  FOR trade_item IN
    SELECT 
      resource,
      CASE resource
        WHEN 'ore' THEN v_ship.ore
        WHEN 'organics' THEN v_ship.organics  
        WHEN 'goods' THEN v_ship.goods
        WHEN 'energy' THEN v_ship.energy
      END as qty,
      CASE resource
        WHEN 'ore' THEN v_port.price_ore * calculate_price_multiplier(v_port.ore, v_port.kind) * 1.10
        WHEN 'organics' THEN v_port.price_organics * calculate_price_multiplier(v_port.organics, v_port.kind) * 1.10
        WHEN 'goods' THEN v_port.price_goods * calculate_price_multiplier(v_port.goods, v_port.kind) * 1.10
        WHEN 'energy' THEN v_port.price_energy * calculate_price_multiplier(v_port.energy, v_port.kind) * 1.10
      END as unit_price
    FROM (VALUES ('ore'), ('organics'), ('goods'), ('energy')) t(resource)
    WHERE resource != pc
  LOOP
    IF trade_item->>'qty' IS NOT NULL AND (trade_item->>'qty')::int > 0 THEN
      proceeds := (trade_item->>'qty')::int * (trade_item->>'unit_price')::numeric;
      total_proceeds := total_proceeds + proceeds;
      
      -- Add to trade summary
      trade_summary := trade_summary || jsonb_build_object(
        'action', 'sell',
        'resource', trade_item->>'resource',
        'quantity', trade_item->>'qty',
        'unit_price', trade_item->>'unit_price',
        'total', proceeds
      );
    END IF;
  END LOOP;

  -- Buy maximum native commodity possible
  DECLARE
    max_buy INTEGER;
    buy_cost NUMERIC;
    buy_qty INTEGER;
  BEGIN
    max_buy := LEAST(
      CASE pc
        WHEN 'ore' THEN v_port.ore
        WHEN 'organics' THEN v_port.organics
        WHEN 'goods' THEN v_port.goods
        WHEN 'energy' THEN v_port.energy
      END,
      v_ship.cargo - (
        CASE WHEN pc != 'ore' THEN v_ship.ore ELSE 0 END +
        CASE WHEN pc != 'organics' THEN v_ship.organics ELSE 0 END +
        CASE WHEN pc != 'goods' THEN v_ship.goods ELSE 0 END +
        CASE WHEN pc != 'energy' THEN v_ship.energy ELSE 0 END
      ),
      FLOOR((v_player.credits + total_proceeds) / sell_price)
    );
    
    IF max_buy > 0 THEN
      buy_cost := max_buy * sell_price;
      buy_qty := max_buy;
      
      -- Add to trade summary
      trade_summary := trade_summary || jsonb_build_object(
        'action', 'buy',
        'resource', pc,
        'quantity', buy_qty,
        'unit_price', sell_price,
        'total', buy_cost
      );
    ELSE
      buy_qty := 0;
      buy_cost := 0;
    END IF;
  END;

  -- Execute all trades atomically
  BEGIN
    -- Update player credits
    UPDATE players SET credits = v_player.credits + total_proceeds - buy_cost WHERE id = v_player.id;
    
    -- Clear non-native cargo
    UPDATE ships SET 
      ore = CASE WHEN pc != 'ore' THEN 0 ELSE ore END,
      organics = CASE WHEN pc != 'organics' THEN 0 ELSE organics END,
      goods = CASE WHEN pc != 'goods' THEN 0 ELSE goods END,
      energy = CASE WHEN pc != 'energy' THEN 0 ELSE energy END
    WHERE id = v_ship.id;
    
    -- Add native cargo
    CASE pc
      WHEN 'ore' THEN UPDATE ships SET ore = ore + buy_qty WHERE id = v_ship.id;
      WHEN 'organics' THEN UPDATE ships SET organics = organics + buy_qty WHERE id = v_ship.id;
      WHEN 'goods' THEN UPDATE ships SET goods = goods + buy_qty WHERE id = v_ship.id;
      WHEN 'energy' THEN UPDATE ships SET energy = energy + buy_qty WHERE id = v_ship.id;
    END CASE;
    
    -- Update port stock
    CASE pc
      WHEN 'ore' THEN UPDATE ports SET ore = ore - buy_qty WHERE id = v_port.id;
      WHEN 'organics' THEN UPDATE ports SET organics = organics - buy_qty WHERE id = v_port.id;
      WHEN 'goods' THEN UPDATE ports SET goods = goods - buy_qty WHERE id = v_port.id;
      WHEN 'energy' THEN UPDATE ports SET energy = energy - buy_qty WHERE id = v_port.id;
    END CASE;
    
    -- Add non-native stock to port
    UPDATE ports SET
      ore = ore + CASE WHEN pc != 'ore' THEN v_ship.ore ELSE 0 END,
      organics = organics + CASE WHEN pc != 'organics' THEN v_ship.organics ELSE 0 END,
      goods = goods + CASE WHEN pc != 'goods' THEN v_ship.goods ELSE 0 END,
      energy = energy + CASE WHEN pc != 'energy' THEN v_ship.energy ELSE 0 END
    WHERE id = v_port.id;
    
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'trade_failed', 'message', 'Trade execution failed'));
  END;

  RETURN jsonb_build_object(
    'success', true,
    'trades', trade_summary,
    'total_proceeds', total_proceeds,
    'net_profit', total_proceeds - buy_cost,
    'new_credits', v_player.credits + total_proceeds - buy_cost
  );
END;
$$;


ALTER FUNCTION "public"."auto_trade"("p_user_id" "uuid", "p_port_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."build_planet_base"("p_user_id" "uuid", "p_planet_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_planet RECORD;
    v_ship RECORD;
    v_universe_settings RECORD;
    v_base_cost BIGINT;
    v_colonists_required BIGINT;
    v_resources_required BIGINT;
    v_result JSON;
BEGIN
    -- Get player info
    SELECT p.id INTO v_player_id
    FROM players p 
    WHERE p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Player not found'));
    END IF;
    
    -- Get planet info and verify ownership
    SELECT * INTO v_planet
    FROM planets pl
    WHERE pl.id = p_planet_id AND pl.owner_player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Planet not found or not owned by player'));
    END IF;
    
    -- Check if base already exists
    IF v_planet.base_built THEN
        RETURN json_build_object('error', json_build_object('code', 'already_exists', 'message', 'Planet base already built'));
    END IF;
    
    -- Get ship info for credit check
    SELECT * INTO v_ship
    FROM ships s
    WHERE s.player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Ship not found'));
    END IF;
    
    -- Get universe settings
    SELECT 
        us.planet_base_cost,
        us.planet_base_colonists_required,
        us.planet_base_resources_required
    INTO v_universe_settings
    FROM planets pl
    JOIN sectors s ON pl.sector_id = s.id
    JOIN universe_settings us ON s.universe_id = us.universe_id
    WHERE pl.id = p_planet_id;
    
    -- Set defaults if settings not found
    v_base_cost := COALESCE(v_universe_settings.planet_base_cost, 50000);
    v_colonists_required := COALESCE(v_universe_settings.planet_base_colonists_required, 10000);
    v_resources_required := COALESCE(v_universe_settings.planet_base_resources_required, 10000);
    
    -- Check requirements
    IF v_planet.colonists < v_colonists_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough colonists (need ' || v_colonists_required || ', have ' || v_planet.colonists || ')'));
    END IF;
    
    IF v_planet.ore < v_resources_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough ore (need ' || v_resources_required || ', have ' || v_planet.ore || ')'));
    END IF;
    
    IF v_planet.organics < v_resources_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough organics (need ' || v_resources_required || ', have ' || v_planet.organics || ')'));
    END IF;
    
    IF v_planet.goods < v_resources_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough goods (need ' || v_resources_required || ', have ' || v_planet.goods || ')'));
    END IF;
    
    IF v_planet.energy < v_resources_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough energy (need ' || v_resources_required || ', have ' || v_planet.energy || ')'));
    END IF;
    
    IF v_ship.credits < v_base_cost THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_funds', 'message', 'Not enough credits (need ' || v_base_cost || ', have ' || v_ship.credits || ')'));
    END IF;
    
    -- Build the base (consume resources and credits)
    UPDATE planets
    SET 
        base_built = TRUE,
        ore = ore - v_resources_required,
        organics = organics - v_resources_required,
        goods = goods - v_resources_required,
        energy = energy - v_resources_required
    WHERE id = p_planet_id;
    
    UPDATE ships
    SET credits = credits - v_base_cost
    WHERE player_id = v_player_id;
    
    -- Check for sector ownership
    PERFORM check_sector_ownership(v_planet.sector_id);
    
    v_result := json_build_object(
        'success', TRUE,
        'message', 'Planet base built successfully',
        'planet_id', p_planet_id,
        'base_cost', v_base_cost,
        'resources_consumed', v_resources_required
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', json_build_object('code', 'internal_error', 'message', 'Failed to build planet base'));
END;
$$;


ALTER FUNCTION "public"."build_planet_base"("p_user_id" "uuid", "p_planet_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_bnt_capacity"("tech_level" integer) RETURNS bigint
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
BEGIN
    -- BNT formula: 100 * (1.5^tech_level)
    -- Round to nearest integer
    RETURN ROUND(100 * POWER(1.5, tech_level));
END;
$$;


ALTER FUNCTION "public"."calculate_bnt_capacity"("tech_level" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."calculate_bnt_capacity"("tech_level" integer) IS 'Calculates ship capacity using classic BNT formula: 100 * (1.5^tech_level)';



CREATE OR REPLACE FUNCTION "public"."calculate_economic_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_score_big BIGINT := 0;
  v_credits_big BIGINT := 0;
  v_planet_credits_big BIGINT := 0;
  v_trading_volume_big BIGINT := 0;
  v_port_influence INT := 0;
BEGIN
  -- Ship credits (no cap here; we will dampen below)
  SELECT COALESCE(COALESCE(s.credits, 0), 0)::BIGINT
  INTO v_credits_big
  FROM players p
  JOIN ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  -- Sum of owned planet credits (banked)
  SELECT COALESCE(SUM(pl.credits), 0)::BIGINT
  INTO v_planet_credits_big
  FROM planets pl
  JOIN sectors sx ON pl.sector_id = sx.id
  WHERE pl.owner_player_id = p_player_id AND sx.universe_id = p_universe_id;

  -- Total trading volume (buy/sell qty * price) as BIGINT
  SELECT COALESCE(SUM(
    CASE 
      WHEN action = 'buy' THEN (qty::BIGINT) * (price::BIGINT)
      WHEN action = 'sell' THEN (qty::BIGINT) * (price::BIGINT)
      ELSE 0
    END
  ), 0)
  INTO v_trading_volume_big
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  -- Unique ports traded at
  SELECT COUNT(DISTINCT port_id) INTO v_port_influence
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  -- Economic score emphasizing assets with a Credits->Score ratio of ~1:0.000001
  -- so 10,000,000,000 credits ~ 10,000 score before category weighting.
  --   credits_term = (ship_credits + planet_credits) / 100000
  --   trade_term   = trade_volume / 10000000
  --   ports_term   = ports_traded * 1
  v_score_big := LEAST(((GREATEST(0, v_credits_big + v_planet_credits_big)) / 100000), 2147483647)
                  + LEAST((v_trading_volume_big / 10000000), 2147483647)
                  + LEAST((v_port_influence::BIGINT * 1), 2147483647);

  RETURN GREATEST(0, LEAST(v_score_big, 2147483647))::INTEGER;
END;
$$;


ALTER FUNCTION "public"."calculate_economic_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_exploration_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_score_big BIGINT := 0;
  v_sectors_visited INT := 0;
  v_warp_discoveries INT := 0;
  v_universe_size INT := 0;
BEGIN
  SELECT COUNT(DISTINCT v.sector_id) INTO v_sectors_visited
  FROM visited v
  JOIN players p ON v.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  v_warp_discoveries := 0; -- placeholder

  SELECT COUNT(*) INTO v_universe_size
  FROM sectors
  WHERE universe_id = p_universe_id;

  v_score_big := LEAST((v_sectors_visited::BIGINT * 50), 2147483647)
                  + LEAST(((v_sectors_visited::BIGINT * 1000) / GREATEST(1, v_universe_size)), 2147483647)
                  + LEAST(v_warp_discoveries::BIGINT, 2147483647);

  RETURN GREATEST(0, LEAST(v_score_big, 2147483647))::INTEGER;
END;
$$;


ALTER FUNCTION "public"."calculate_exploration_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_military_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_score_big BIGINT := 0;
  v_ship_levels_big BIGINT := 0;
  v_combat_victories INT := 0;
BEGIN
  -- Sum of ship upgrade levels * 100
  SELECT COALESCE(((s.engine_lvl + s.comp_lvl + s.sensor_lvl + s.shield_lvl + s.hull_lvl)::BIGINT * 100), 0)
  INTO v_ship_levels_big
  FROM ships s
  JOIN players p ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;

  -- Placeholder for future victories
  v_combat_victories := 0;

  v_score_big := LEAST(v_ship_levels_big, 2147483647) 
                  + LEAST((v_combat_victories::BIGINT * 500), 2147483647);

  RETURN GREATEST(0, LEAST(v_score_big, 2147483647))::INTEGER;
END;
$$;


ALTER FUNCTION "public"."calculate_military_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_player_score"("p_player_id" "uuid") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_ship_value BIGINT := 0;
    v_credits BIGINT := 0;
    v_planet_value BIGINT := 0;
    v_exploration_score BIGINT := 0;
    v_total_score BIGINT := 0;
BEGIN
    -- Calculate ship value based on tech levels (original multipliers)
    SELECT 
        COALESCE(
            (engine_lvl * 100000) +
            (power_lvl * 150000) +
            (comp_lvl * 200000) +
            (sensor_lvl * 175000) +
            (beam_lvl * 300000) +
            (armor_max * 100) +          -- Use armor_max instead of armor_lvl
            (cloak_lvl * 400000) +
            (torp_launcher_lvl * 350000) +
            (shield_lvl * 250000),
            0
        )
    INTO v_ship_value
    FROM ships 
    WHERE player_id = p_player_id;

    -- Get ship credits with reduced weight (0.5x instead of 1x)
    SELECT COALESCE(credits, 0) INTO v_credits
    FROM ships 
    WHERE player_id = p_player_id;

    -- Calculate total planet value (commodities + colonists + credits)
    SELECT COALESCE(
        SUM(
            (ore * 1) +           -- Ore worth 1 credit each
            (organics * 2) +      -- Organics worth 2 credits each
            (goods * 5) +         -- Goods worth 5 credits each
            (energy * 3) +        -- Energy worth 3 credits each
            (colonists * 10) +    -- Colonists worth 10 credits each
            (fighters * 50) +     -- Fighters worth 50 credits each
            (torpedoes * 25) +    -- Torpedoes worth 25 credits each
            COALESCE(credits, 0)  -- Planet credits
        ), 0
    ) INTO v_planet_value
    FROM planets 
    WHERE owner_player_id = p_player_id;

    -- Calculate exploration score (sectors visited * 1000)
    SELECT COALESCE(turns_spent * 100, 0) INTO v_exploration_score
    FROM players 
    WHERE id = p_player_id;

    -- Calculate total score with original scaling, just reduce credit weight
    -- Credits now count for 0.5x instead of 1x to smooth score jumps
    v_total_score := (v_ship_value + (v_credits * 0.5) + v_planet_value + v_exploration_score) / 10000;

    RETURN GREATEST(0, v_total_score);
END;
$$;


ALTER FUNCTION "public"."calculate_player_score"("p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_price_multiplier"("current_stock" integer, "port_kind" "text" DEFAULT 'ore'::"text", "base_stock" integer DEFAULT NULL::integer) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
  v_base_stock INTEGER;
  stock_ratio NUMERIC;
  log_factor NUMERIC;
  multiplier NUMERIC;
BEGIN
  -- Set port-type-specific base stock levels (matching live BNT screenshots)
  IF base_stock IS NULL THEN
    CASE port_kind
      WHEN 'ore' THEN v_base_stock := 100000000;      -- 100M (matches live BNT)
      WHEN 'organics' THEN v_base_stock := 100000000; -- 100M (matches live BNT)
      WHEN 'goods' THEN v_base_stock := 100000000;     -- 100M (matches live BNT)
      WHEN 'energy' THEN v_base_stock := 1000000000;   -- 1B (matches live BNT)
      ELSE v_base_stock := 100000000;                  -- Default to 100M
    END CASE;
  ELSE
    v_base_stock := base_stock;
  END IF;
  
  -- Handle depleted stock (maximum price spike)
  IF current_stock <= 0 THEN
    RETURN 2.0; -- 200% of base price when completely out of stock
  END IF;
  
  -- Calculate stock ratio
  stock_ratio := current_stock::NUMERIC / v_base_stock;
  
  -- Use logarithmic scaling for smooth price transitions
  log_factor := LOG(10, GREATEST(stock_ratio, 0.01)); -- Clamp to avoid log(0)
  
  -- Scale log factor to price range (0.5 to 2.0)
  multiplier := 2.0 - (log_factor + 2) * 0.5; -- log(0.01) ≈ -2, log(100) ≈ 2
  multiplier := GREATEST(0.5, LEAST(2.0, multiplier)); -- Clamp to range
  
  RETURN multiplier;
END;
$$;


ALTER FUNCTION "public"."calculate_price_multiplier"("current_stock" integer, "port_kind" "text", "base_stock" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_route_profitability"("p_user_id" "uuid", "p_route_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_route RECORD;
    v_waypoint RECORD;
    v_total_profit BIGINT := 0;
    v_total_turns INTEGER := 0;
    v_cargo_capacity INTEGER;
    v_engine_level INTEGER;
    v_current_sector INTEGER;
    v_previous_sector INTEGER;
    v_distance INTEGER;
    v_turn_cost INTEGER;
    v_profit_per_turn NUMERIC;
    v_market_conditions JSONB := '{}'::jsonb;
    v_result JSON;
BEGIN
    -- Verify route ownership
    SELECT tr.*, p.id as player_id, s.engine_lvl, s.cargo, p.current_sector
    INTO v_route
    FROM trade_routes tr
    JOIN players p ON tr.player_id = p.id
    JOIN ships s ON s.player_id = p.id
    WHERE tr.id = p_route_id AND p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'route_not_found', 'message', 'Route not found or access denied'));
    END IF;
    
    v_cargo_capacity := v_route.cargo;
    v_engine_level := v_route.engine_lvl;
    
    -- Get current sector number
    SELECT s.number INTO v_current_sector
    FROM sectors s
    WHERE s.id = v_route.current_sector;
    
    v_previous_sector := v_current_sector;
    
    -- Calculate profitability for each waypoint
    FOR v_waypoint IN 
        SELECT rw.*, p.kind as port_kind, s.number as sector_number,
               p.price_ore, p.price_organics, p.price_goods, p.price_energy,
               p.ore as stock_ore, p.organics as stock_organics, 
               p.goods as stock_goods, p.energy as stock_energy
        FROM route_waypoints rw
        JOIN ports p ON rw.port_id = p.id
        JOIN sectors s ON p.sector_id = s.id
        WHERE rw.route_id = p_route_id
        ORDER BY rw.sequence_order
    LOOP
        -- Calculate travel cost
        v_distance := ABS(v_waypoint.sector_number - v_previous_sector);
        v_turn_cost := GREATEST(1, CEIL(v_distance::NUMERIC / GREATEST(v_engine_level, 1)));
        v_total_turns := v_total_turns + v_turn_cost;
        
        -- Calculate profit based on action type
        CASE v_waypoint.action_type
            WHEN 'buy' THEN
                -- Buying native commodity at port
                CASE v_waypoint.resource
                    WHEN 'ore' THEN v_total_profit := v_total_profit - (v_cargo_capacity * v_waypoint.price_ore * 0.9);
                    WHEN 'organics' THEN v_total_profit := v_total_profit - (v_cargo_capacity * v_waypoint.price_organics * 0.9);
                    WHEN 'goods' THEN v_total_profit := v_total_profit - (v_cargo_capacity * v_waypoint.price_goods * 0.9);
                    WHEN 'energy' THEN v_total_profit := v_total_profit - (v_cargo_capacity * v_waypoint.price_energy * 0.9);
                END CASE;
            WHEN 'sell' THEN
                -- Selling non-native commodity at port
                CASE v_waypoint.resource
                    WHEN 'ore' THEN v_total_profit := v_total_profit + (v_cargo_capacity * v_waypoint.price_ore * 1.1);
                    WHEN 'organics' THEN v_total_profit := v_total_profit + (v_cargo_capacity * v_waypoint.price_organics * 1.1);
                    WHEN 'goods' THEN v_total_profit := v_total_profit + (v_cargo_capacity * v_waypoint.price_goods * 1.1);
                    WHEN 'energy' THEN v_total_profit := v_total_profit + (v_cargo_capacity * v_waypoint.price_energy * 1.1);
                END CASE;
            WHEN 'trade_auto' THEN
                -- Auto-trade: sell all non-native, buy native
                -- Simplified calculation - would need more complex logic for actual implementation
                v_total_profit := v_total_profit + (v_cargo_capacity * 5); -- Placeholder
        END CASE;
        
        -- Store market conditions
        v_market_conditions := v_market_conditions || jsonb_build_object(
            'sector_' || v_waypoint.sector_number, jsonb_build_object(
                'port_kind', v_waypoint.port_kind,
                'prices', jsonb_build_object(
                    'ore', v_waypoint.price_ore,
                    'organics', v_waypoint.price_organics,
                    'goods', v_waypoint.price_goods,
                    'energy', v_waypoint.price_energy
                ),
                'stock', jsonb_build_object(
                    'ore', v_waypoint.stock_ore,
                    'organics', v_waypoint.stock_organics,
                    'goods', v_waypoint.stock_goods,
                    'energy', v_waypoint.stock_energy
                )
            )
        );
        
        v_previous_sector := v_waypoint.sector_number;
    END LOOP;
    
    -- Calculate profit per turn
    IF v_total_turns > 0 THEN
        v_profit_per_turn := v_total_profit::NUMERIC / v_total_turns;
    ELSE
        v_profit_per_turn := 0;
    END IF;
    
    -- Store profitability data
    INSERT INTO route_profitability (
        route_id, estimated_profit_per_cycle, estimated_turns_per_cycle, 
        profit_per_turn, cargo_efficiency, market_conditions
    )
    VALUES (
        p_route_id, v_total_profit, v_total_turns, 
        v_profit_per_turn, v_profit_per_turn / GREATEST(v_cargo_capacity, 1), v_market_conditions
    );
    
    -- Mark previous calculations as not current
    UPDATE route_profitability 
    SET is_current = false 
    WHERE route_id = p_route_id AND id != (SELECT id FROM route_profitability WHERE route_id = p_route_id ORDER BY calculated_at DESC LIMIT 1);
    
    RETURN json_build_object(
        'ok', true,
        'estimated_profit_per_cycle', v_total_profit,
        'estimated_turns_per_cycle', v_total_turns,
        'profit_per_turn', v_profit_per_turn,
        'cargo_efficiency', v_profit_per_turn / GREATEST(v_cargo_capacity, 1),
        'message', 'Route profitability calculated successfully'
    );
END;
$$;


ALTER FUNCTION "public"."calculate_route_profitability"("p_user_id" "uuid", "p_route_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_ship_avg_tech_level"("p_player_id" "uuid") RETURNS numeric
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_ship RECORD;
    v_avg_tech numeric;
BEGIN
    -- Get ship data
    SELECT 
        hull_lvl,
        engine_lvl,
        comp_lvl,
        sensor_lvl,
        shield_lvl,
        power_lvl,
        beam_lvl,
        torp_launcher_lvl,
        cloak_lvl
    INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    
    -- Calculate average tech level
    v_avg_tech := (
        v_ship.hull_lvl + 
        v_ship.engine_lvl + 
        v_ship.comp_lvl + 
        v_ship.sensor_lvl + 
        v_ship.shield_lvl + 
        v_ship.power_lvl + 
        v_ship.beam_lvl + 
        v_ship.torp_launcher_lvl + 
        v_ship.cloak_lvl
    ) / 9.0;
    
    RETURN v_avg_tech;
END;
$$;


ALTER FUNCTION "public"."calculate_ship_avg_tech_level"("p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_ship_capacity"("p_ship_id" "uuid", "p_capacity_type" "text") RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  ship_record RECORD;
  capacity INTEGER := 0;
BEGIN
  -- Get ship data
  SELECT * INTO ship_record FROM ships WHERE id = p_ship_id;
  
  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  
  -- Calculate capacity based on type
  CASE p_capacity_type
    WHEN 'fighters' THEN
      -- Fighters limited by computer level (comp_lvl)
      -- Formula: comp_lvl * 10 (standard BNT formula)
      capacity := ship_record.comp_lvl * 10;
      
    WHEN 'torpedoes' THEN
      -- Torpedoes limited by torpedo launcher level (torp_launcher_lvl)
      -- Formula: torp_launcher_lvl * 10 (standard BNT formula)
      capacity := ship_record.torp_launcher_lvl * 10;
      
    WHEN 'armor' THEN
      -- Armor limited by armor level (calculated from armor_max)
      -- Formula: armor_max (already calculated based on armor level)
      capacity := ship_record.armor_max;
      
    WHEN 'colonists' THEN
      -- Colonists limited by cargo space (hull level)
      -- Same as commodity cargo space
      capacity := ship_record.cargo;
      
    WHEN 'energy' THEN
      -- Energy limited by power level (power_lvl)
      -- Formula: power_lvl * 100 (standard BNT formula)
      capacity := ship_record.power_lvl * 100;
      
    ELSE
      capacity := 0;
  END CASE;
  
  RETURN GREATEST(capacity, 0);
END;
$$;


ALTER FUNCTION "public"."calculate_ship_capacity"("p_ship_id" "uuid", "p_capacity_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_territorial_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_score_big BIGINT := 0;
  v_planets_owned INT := 0;
  v_planet_development_big BIGINT := 0;
  v_sectors_controlled INT := 0;
BEGIN
  SELECT COUNT(*) INTO v_planets_owned
  FROM planets pl
  JOIN sectors s ON pl.sector_id = s.id
  WHERE pl.owner_player_id = p_player_id AND s.universe_id = p_universe_id;

  -- Simple development metric for now
  v_planet_development_big := (v_planets_owned::BIGINT * 100);

  SELECT COUNT(DISTINCT s.id) INTO v_sectors_controlled
  FROM planets pl
  JOIN sectors s ON pl.sector_id = s.id
  WHERE pl.owner_player_id = p_player_id AND s.universe_id = p_universe_id;

  v_score_big := LEAST((v_planets_owned::BIGINT * 1000), 2147483647)
                  + LEAST((v_sectors_controlled::BIGINT * 500), 2147483647)
                  + LEAST(v_planet_development_big, 2147483647);

  RETURN GREATEST(0, LEAST(v_score_big, 2147483647))::INTEGER;
END;
$$;


ALTER FUNCTION "public"."calculate_territorial_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_total_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_economic INT;
  v_territorial INT;
  v_military INT;
  v_exploration INT;
  v_total_big BIGINT;
BEGIN
  v_economic := calculate_economic_score(p_player_id, p_universe_id);
  v_territorial := calculate_territorial_score(p_player_id, p_universe_id);
  v_military := calculate_military_score(p_player_id, p_universe_id);
  v_exploration := calculate_exploration_score(p_player_id, p_universe_id);

  v_total_big := (v_economic::BIGINT * 40) 
                  + (v_territorial::BIGINT * 25) 
                  + (v_military::BIGINT * 20) 
                  + (v_exploration::BIGINT * 15);
  -- divide by 100 using BIGINT math
  v_total_big := v_total_big / 100;

  RETURN json_build_object(
    'economic', v_economic,
    'territorial', v_territorial,
    'military', v_military,
    'exploration', v_exploration,
    'total', GREATEST(0, LEAST(v_total_big, 2147483647))::INTEGER
  );
END;
$$;


ALTER FUNCTION "public"."calculate_total_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_ai_health"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_total_ai int;
  v_active_ai int;
  v_stuck_ai int;
  v_low_credits_ai int;
  v_no_turns_ai int;
  v_avg_efficiency numeric;
BEGIN
  -- Count AI players by status
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  SELECT COUNT(*) INTO v_active_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  SELECT COUNT(*) INTO v_no_turns_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) <= 0;
  
  SELECT COUNT(*) INTO v_low_credits_ai
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND s.credits < 100;
  
  -- Calculate average efficiency
  SELECT COALESCE(AVG(m.efficiency_score), 0) INTO v_avg_efficiency
  FROM public.ai_player_memory m
  JOIN public.players p ON p.id = m.player_id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  RETURN jsonb_build_object(
    'total_ai_players', v_total_ai,
    'active_ai_players', v_active_ai,
    'ai_without_turns', v_no_turns_ai,
    'ai_low_credits', v_low_credits_ai,
    'average_efficiency', ROUND(v_avg_efficiency, 3),
    'health_status', CASE 
      WHEN v_active_ai = 0 THEN 'critical'
      WHEN v_active_ai < v_total_ai * 0.5 THEN 'poor'
      WHEN v_avg_efficiency < 0.3 THEN 'fair'
      ELSE 'good'
    END
  );
END;
$$;


ALTER FUNCTION "public"."check_ai_health"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_sector_ownership"("p_sector_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_sector RECORD;
    v_planets_with_bases INTEGER;
    v_ownership_threshold INTEGER;
    v_top_player RECORD;
    v_result JSON;
BEGIN
    -- Get sector info
    SELECT * INTO v_sector
    FROM sectors s
    WHERE s.id = p_sector_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Sector not found'));
    END IF;
    
    -- Get ownership threshold from universe settings
    SELECT us.sector_ownership_threshold INTO v_ownership_threshold
    FROM universe_settings us
    WHERE us.universe_id = v_sector.universe_id;
    
    v_ownership_threshold := COALESCE(v_ownership_threshold, 3);
    
    -- Count planets with bases in this sector
    SELECT COUNT(*) INTO v_planets_with_bases
    FROM planets p
    WHERE p.sector_id = p_sector_id AND p.base_built = TRUE;
    
    -- If threshold met, find player with most bases
    IF v_planets_with_bases >= v_ownership_threshold THEN
        SELECT 
            p.owner_player_id,
            COUNT(*) as base_count
        INTO v_top_player
        FROM planets p
        WHERE p.sector_id = p_sector_id AND p.base_built = TRUE
        GROUP BY p.owner_player_id
        ORDER BY base_count DESC
        LIMIT 1;
        
        -- Update sector ownership
        UPDATE sectors
        SET 
            owner_player_id = v_top_player.owner_player_id,
            controlled = TRUE,
            name = (SELECT handle FROM players WHERE id = v_top_player.owner_player_id) || '''s Sector'
        WHERE id = p_sector_id;
        
        v_result := json_build_object(
            'success', TRUE,
            'message', 'Sector ownership updated',
            'sector_id', p_sector_id,
            'owner_player_id', v_top_player.owner_player_id,
            'sector_name', (SELECT handle FROM players WHERE id = v_top_player.owner_player_id) || '''s Sector'
        );
    ELSE
        v_result := json_build_object(
            'success', TRUE,
            'message', 'Sector ownership threshold not met',
            'sector_id', p_sector_id,
            'planets_with_bases', v_planets_with_bases,
            'threshold', v_ownership_threshold
        );
    END IF;
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', json_build_object('code', 'internal_error', 'message', 'Failed to check sector ownership'));
END;
$$;


ALTER FUNCTION "public"."check_sector_ownership"("p_sector_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_sector_permission"("p_sector_id" "uuid", "p_player_id" "uuid", "p_action" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_sector RECORD;
  v_rule_value TEXT;
  v_is_owner BOOLEAN;
  v_is_ally BOOLEAN := false; -- TODO: Implement alliance system
BEGIN
  -- Get sector rules and ownership
  SELECT 
    owner_player_id,
    allow_attacking,
    allow_trading,
    allow_planet_creation,
    allow_sector_defense,
    number
  INTO v_sector
  FROM public.sectors
  WHERE id = p_sector_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'sector_not_found');
  END IF;

  -- Check if player owns the sector
  v_is_owner := (v_sector.owner_player_id = p_player_id);

  -- Get the relevant rule based on action
  CASE p_action
    WHEN 'attack' THEN
      IF NOT v_sector.allow_attacking THEN
        RETURN jsonb_build_object(
          'allowed', false, 
          'reason', 'combat_disabled',
          'message', 'Combat is not allowed in this sector.'
        );
      END IF;
      v_rule_value := 'yes'; -- Attacking is boolean, so if true we allow
      
    WHEN 'trade' THEN
      v_rule_value := v_sector.allow_trading;
      
    WHEN 'create_planet' THEN
      v_rule_value := v_sector.allow_planet_creation;
      
    WHEN 'deploy_defense' THEN
      v_rule_value := v_sector.allow_sector_defense;
      
    ELSE
      RETURN jsonb_build_object('allowed', false, 'reason', 'invalid_action');
  END CASE;

  -- For non-attack actions, check text rules
  IF p_action != 'attack' THEN
    IF v_rule_value = 'no' THEN
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'action_disabled',
        'message', 'This action is not allowed in this sector.'
      );
    ELSIF v_rule_value = 'allies_only' AND NOT v_is_owner AND NOT v_is_ally THEN
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'allies_only',
        'message', 'This action is restricted to the sector owner and their allies.'
      );
    END IF;
  END IF;

  -- Permission granted
  RETURN jsonb_build_object('allowed', true);
END;
$$;


ALTER FUNCTION "public"."check_sector_permission"("p_sector_id" "uuid", "p_player_id" "uuid", "p_action" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."check_sector_permission"("p_sector_id" "uuid", "p_player_id" "uuid", "p_action" "text") IS 'Validates if a player can perform an action in a sector based on sector rules';



CREATE OR REPLACE FUNCTION "public"."check_warp_degree"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_universe uuid := NEW.universe_id;
  v_from uuid;
  v_to uuid;
  v_cap int := 15;
  v_deg_from int;
  v_deg_to int;
BEGIN
  -- Allow for either column naming
  BEGIN v_from := NEW.from_sector; EXCEPTION WHEN undefined_column THEN v_from := NEW.from_sector_id; END;
  BEGIN v_to   := NEW.to_sector;   EXCEPTION WHEN undefined_column THEN v_to   := NEW.to_sector_id;   END;

  -- Load cap from universe_settings if present
  BEGIN
    SELECT COALESCE(max_links_per_sector, 15) INTO v_cap FROM universe_settings WHERE universe_id = v_universe LIMIT 1;
  EXCEPTION WHEN undefined_column THEN v_cap := 15; END;

  -- Compute undirected degree for both endpoints AFTER this insert
  SELECT COUNT(*) INTO v_deg_from FROM (
    SELECT DISTINCT CASE WHEN w.from_sector = v_from THEN w.to_sector ELSE w.from_sector END AS nbr
    FROM warps w
    WHERE w.universe_id = v_universe AND (w.from_sector = v_from OR w.to_sector = v_from)
    UNION ALL
    SELECT DISTINCT v_to
  ) q;

  SELECT COUNT(*) INTO v_deg_to FROM (
    SELECT DISTINCT CASE WHEN w.from_sector = v_to THEN w.to_sector ELSE w.from_sector END AS nbr
    FROM warps w
    WHERE w.universe_id = v_universe AND (w.from_sector = v_to OR w.to_sector = v_to)
    UNION ALL
    SELECT DISTINCT v_from
  ) q2;

  IF v_deg_from > v_cap OR v_deg_to > v_cap THEN
    RAISE EXCEPTION 'Warp cap exceeded (cap=%, from deg=%, to deg=%)', v_cap, v_deg_from, v_deg_to;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_warp_degree"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_orphaned_player_data"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_orphaned_players INTEGER := 0;
  v_orphaned_ships INTEGER := 0;
  v_orphaned_planets INTEGER := 0;
  v_first_universe RECORD;
BEGIN
  -- Count orphaned data
  SELECT COUNT(*) INTO v_orphaned_players 
  FROM players p 
  WHERE p.user_id = p_user_id 
  AND NOT EXISTS(SELECT 1 FROM universes u WHERE u.id = p.universe_id);
  
  SELECT COUNT(*) INTO v_orphaned_ships 
  FROM ships s 
  JOIN players p ON s.player_id = p.id
  WHERE p.user_id = p_user_id 
  AND NOT EXISTS(SELECT 1 FROM universes u WHERE u.id = p.universe_id);
  
  SELECT COUNT(*) INTO v_orphaned_planets 
  FROM planets pl
  JOIN sectors sec ON pl.sector_id = sec.id
  WHERE pl.owner_player_id IN (SELECT id FROM players WHERE user_id = p_user_id)
  AND NOT EXISTS(SELECT 1 FROM universes u WHERE u.id = sec.universe_id);
  
  -- Get first available universe for potential migration
  SELECT * INTO v_first_universe FROM public.get_first_available_universe();
  
  RETURN jsonb_build_object(
    'orphaned_players', v_orphaned_players,
    'orphaned_ships', v_orphaned_ships,
    'orphaned_planets', v_orphaned_planets,
    'first_available_universe', CASE 
      WHEN v_first_universe.universe_id IS NOT NULL THEN 
        jsonb_build_object('id', v_first_universe.universe_id, 'name', v_first_universe.universe_name)
      ELSE NULL 
    END,
    'has_orphaned_data', (v_orphaned_players > 0 OR v_orphaned_ships > 0 OR v_orphaned_planets > 0)
  );
END;
$$;


ALTER FUNCTION "public"."cleanup_orphaned_player_data"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_ai_players"("p_universe_id" "uuid", "p_count" integer DEFAULT 5) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    ai_player RECORD;
    ai_ship RECORD;
    created_count INTEGER := 0;
    ai_name TEXT;
    v_sector_id UUID;
    v_result JSON;
BEGIN
    -- Log the start of the function
    RAISE NOTICE 'Starting create_ai_players for universe_id: %, count: %', p_universe_id, p_count;
    
    -- Get a random sector to start AI players in
    SELECT id INTO v_sector_id
    FROM public.sectors
    WHERE universe_id = p_universe_id
    ORDER BY RANDOM()
    LIMIT 1;
    
    IF v_sector_id IS NULL THEN
        RAISE NOTICE 'No sectors found in universe: %', p_universe_id;
        RETURN json_build_object('error', 'No sectors found in universe');
    END IF;
    
    RAISE NOTICE 'Selected sector_id: % for AI players', v_sector_id;
    
    -- Create AI players
    FOR i IN 1..p_count LOOP
        RAISE NOTICE 'Creating AI player % of %', i, p_count;
        
        -- Generate unique AI name
        ai_name := public.generate_ai_name();
        RAISE NOTICE 'Generated AI name: %', ai_name;
        
        -- Check if name already exists and generate new one if needed
        WHILE EXISTS (SELECT 1 FROM public.players WHERE handle = ai_name AND universe_id = p_universe_id) LOOP
            ai_name := public.generate_ai_name();
            RAISE NOTICE 'Name conflict, generating new name: %', ai_name;
        END LOOP;
        
        -- Create AI player (AI players need a user_id but don't need real user accounts)
        INSERT INTO public.players (handle, universe_id, is_ai, current_sector, user_id)
        VALUES (ai_name, p_universe_id, TRUE, v_sector_id, gen_random_uuid())
        RETURNING * INTO ai_player;
        
        RAISE NOTICE 'Created AI player with ID: %', ai_player.id;
        
        -- Create AI ship with only existing columns (ships don't have sector_id)
        INSERT INTO public.ships (
            player_id,
            credits,
            hull_lvl,
            engine_lvl,
            comp_lvl,
            sensor_lvl,
            shield_lvl
        )
        VALUES (
            ai_player.id,
            10000, -- Starting credits
            1,     -- Basic ship levels
            1,
            1,
            1,
            0      -- No shields initially
        )
        RETURNING * INTO ai_ship;
        
        RAISE NOTICE 'Created AI ship with ID: %', ai_ship.id;
        
        created_count := created_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Successfully created % AI players', created_count;
    
    v_result := json_build_object(
        'success', TRUE,
        'message', 'AI players created successfully',
        'count', created_count,
        'universe_id', p_universe_id
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error creating AI players: %', SQLERRM;
        RETURN json_build_object('error', 'Failed to create AI players: ' || SQLERRM);
END;
$$;


ALTER FUNCTION "public"."create_ai_players"("p_universe_id" "uuid", "p_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text" DEFAULT NULL::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_route_id UUID;
    v_result JSON;
    v_route_count INTEGER;
BEGIN
    -- Get player ID
    SELECT id INTO v_player_id
    FROM players 
    WHERE user_id = p_user_id AND universe_id = p_universe_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found in this universe'));
    END IF;
    
    -- Check trade route limit (10 routes per player)
    SELECT COUNT(*) INTO v_route_count
    FROM trade_routes
    WHERE player_id = v_player_id;
    
    IF v_route_count >= 10 THEN
        RETURN json_build_object('error', json_build_object('code', 'route_limit_exceeded', 'message', 'Maximum of 10 trade routes allowed per player'));
    END IF;
    
    -- Check if route name already exists for this player
    IF EXISTS(SELECT 1 FROM trade_routes WHERE player_id = v_player_id AND name = p_name) THEN
        RETURN json_build_object('error', json_build_object('code', 'name_taken', 'message', 'Route name already exists'));
    END IF;
    
    -- Create the route
    INSERT INTO trade_routes (player_id, universe_id, name, description)
    VALUES (v_player_id, p_universe_id, p_name, p_description)
    RETURNING id INTO v_route_id;
    
    RETURN json_build_object(
        'ok', true,
        'route_id', v_route_id,
        'message', 'Trade route created successfully'
    );
END;
$$;


ALTER FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text" DEFAULT NULL::"text", "p_movement_type" "text" DEFAULT 'warp'::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_route_id UUID;
    v_result JSON;
    v_route_count INTEGER;
BEGIN
    -- Validate movement_type
    IF p_movement_type NOT IN ('warp', 'realspace') THEN
        RETURN json_build_object('error', json_build_object('code', 'invalid_movement_type', 'message', 'Movement type must be warp or realspace'));
    END IF;
    
    -- Get player ID
    SELECT id INTO v_player_id
    FROM players 
    WHERE user_id = p_user_id AND universe_id = p_universe_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found in this universe'));
    END IF;
    
    -- Check trade route limit (10 routes per player)
    SELECT COUNT(*) INTO v_route_count
    FROM trade_routes
    WHERE player_id = v_player_id;
    
    IF v_route_count >= 10 THEN
        RETURN json_build_object('error', json_build_object('code', 'route_limit_exceeded', 'message', 'Maximum of 10 trade routes allowed per player'));
    END IF;
    
    -- Check if route name already exists for this player
    IF EXISTS(SELECT 1 FROM trade_routes WHERE player_id = v_player_id AND name = p_name) THEN
        RETURN json_build_object('error', json_build_object('code', 'name_taken', 'message', 'Route name already exists'));
    END IF;
    
    -- Create the route with movement_type
    INSERT INTO trade_routes (player_id, universe_id, name, description, movement_type)
    VALUES (v_player_id, p_universe_id, p_name, p_description, p_movement_type)
    RETURNING id INTO v_route_id;
    
    RETURN json_build_object(
        'ok', true,
        'route_id', v_route_id,
        'message', 'Trade route created successfully'
    );
END;
$$;


ALTER FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text", "p_movement_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_universe"("p_name" "text", "p_sector_count" integer DEFAULT 100) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_universe_id UUID;
  v_sector_id UUID;
  i INTEGER;
BEGIN
  -- Create universe
  INSERT INTO public.universes (name, sector_count)
  VALUES (p_name, p_sector_count)
  RETURNING id INTO v_universe_id;

  -- Create sectors
  FOR i IN 0..(p_sector_count - 1) LOOP
    INSERT INTO public.sectors (universe_id, number)
    VALUES (v_universe_id, i);
  END LOOP;

  -- Apply Federation rules to sectors 0-10
  PERFORM public.apply_federation_rules(v_universe_id);

  RAISE NOTICE 'Created universe % with % sectors', p_name, p_sector_count;
  
  RETURN v_universe_id;
END;
$$;


ALTER FUNCTION "public"."create_universe"("p_name" "text", "p_sector_count" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."create_universe"("p_name" "text", "p_sector_count" integer) IS 'Creates a new universe with sectors and applies Federation safe zone rules';



CREATE OR REPLACE FUNCTION "public"."create_universe_default_settings"("p_universe_id" "uuid", "p_created_by" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_settings_id UUID;
BEGIN
  INSERT INTO universe_settings (
    universe_id,
    max_accumulated_turns,
    turns_generation_interval_minutes,
    port_regeneration_interval_minutes,
    rankings_generation_interval_minutes,
    defenses_check_interval_minutes,
    xenobes_play_interval_minutes,
    igb_interest_accumulation_interval_minutes,
    news_generation_interval_minutes,
    planet_production_interval_minutes,
    ships_tow_from_fed_sectors_interval_minutes,
    sector_defenses_degrade_interval_minutes,
    planetary_apocalypse_interval_minutes,
    created_by,
    updated_by
  ) VALUES (
    p_universe_id,
    5000, -- max accumulated turns
    3,    -- 3 minutes turn generation
    5,    -- 5 minutes port regeneration
    10,   -- 10 minutes rankings
    15,   -- 15 minutes defenses check
    30,   -- 30 minutes xenobes play
    10,   -- 10 minutes IGB interest
    60,   -- 60 minutes news generation
    15,   -- 15 minutes planet production
    30,   -- 30 minutes ships tow
    60,   -- 60 minutes sector defenses degrade
    1440, -- 1440 minutes planetary apocalypse (24 hours)
    p_created_by,
    p_created_by
  ) RETURNING id INTO v_settings_id;
  
  RETURN v_settings_id;
END;
$$;


ALTER FUNCTION "public"."create_universe_default_settings"("p_universe_id" "uuid", "p_created_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cron_run_ai_actions"("p_universe_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN public.run_ai_player_actions(p_universe_id);
END;
$$;


ALTER FUNCTION "public"."cron_run_ai_actions"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cron_run_ai_actions_safe"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_lock_key bigint;
  v_got_lock boolean;
  v_result jsonb;
BEGIN
  v_lock_key := ('x' || substr(replace(p_universe_id::text, '-', ''), 1, 16))::bit(64)::bigint;
  v_got_lock := pg_try_advisory_lock(v_lock_key);

  IF NOT v_got_lock THEN
    RETURN jsonb_build_object('success', false, 'message', 'busy');
  END IF;

  BEGIN
    -- Use the working AI processor
    SELECT run_ai_actions_working(p_universe_id) INTO v_result;
    
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_build_object(
      'success', false, 
      'message', SQLERRM,
      'ai_total', 0,
      'ai_with_turns', 0,
      'ai_with_goal', 0,
      'actions_taken', 0,
      'players_processed', 0,
      'planets_claimed', 0,
      'upgrades', 0,
      'trades', 0
    );
  END;

  PERFORM pg_advisory_unlock(v_lock_key);
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."cron_run_ai_actions_safe"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."degrade_sector_defenses"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- TODO: Implement sector defense degradation
    -- This should degrade sector defenses over time
    
    RETURN jsonb_build_object(
        'message', 'Sector defenses degrade placeholder - not yet implemented',
        'universe_id', p_universe_id,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."degrade_sector_defenses"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."densify_universe_links"("p_universe_id" "uuid", "p_target_min" integer DEFAULT 8, "p_max_per_sector" integer DEFAULT 15, "p_max_attempts" integer DEFAULT 200000) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_added integer := 0;
  v_attempts integer := 0;
  v_sectors_at_target integer := 0;
  v_from uuid;
  v_to   uuid;
BEGIN
  IF p_universe_id IS NULL THEN
    RETURN jsonb_build_object('error','universe_id_required');
  END IF;

  -- Snapshot undirected degree (unique neighbors either direction)
  CREATE TEMP TABLE tmp_deg AS
  SELECT s.id AS sector_id,
         COALESCE(
           (
             SELECT COUNT(*) FROM (
               SELECT DISTINCT CASE WHEN w.from_sector = s.id THEN w.to_sector ELSE w.from_sector END AS nbr
               FROM warps w
               WHERE w.universe_id = s.universe_id
                 AND (w.from_sector = s.id OR w.to_sector = s.id)
             ) q
           ), 0
         ) AS deg
  FROM sectors s
  WHERE s.universe_id = p_universe_id;

  LOOP
    EXIT WHEN v_attempts >= p_max_attempts;
    v_attempts := v_attempts + 1;

    -- pick a sector under target
    SELECT sector_id INTO v_from
    FROM tmp_deg
    WHERE deg < p_target_min
    ORDER BY deg ASC, random()
    LIMIT 1;

    IF NOT FOUND THEN
      EXIT; -- all at/above target
    END IF;

    -- partner under cap and not already linked
    WITH cand AS (
      SELECT td.sector_id
      FROM tmp_deg td
      WHERE td.sector_id <> v_from
        AND td.deg < p_max_per_sector
        AND NOT EXISTS (
          SELECT 1 FROM warps w
          WHERE w.universe_id = p_universe_id
            AND (
                  (w.from_sector = v_from AND w.to_sector = td.sector_id)
               OR (w.from_sector = td.sector_id AND w.to_sector = v_from)
            )
        )
      ORDER BY td.deg ASC, random()
      LIMIT 1
    )
    SELECT sector_id INTO v_to FROM cand;

    IF NOT FOUND THEN
      -- mark saturated to avoid spinning
      UPDATE tmp_deg SET deg = p_max_per_sector WHERE sector_id = v_from AND deg < p_target_min;
      CONTINUE;
    END IF;

    -- caps check
    IF (SELECT deg FROM tmp_deg WHERE sector_id = v_from) >= p_max_per_sector OR
       (SELECT deg FROM tmp_deg WHERE sector_id = v_to)   >= p_max_per_sector THEN
      CONTINUE;
    END IF;

    BEGIN
      INSERT INTO warps (universe_id, from_sector, to_sector) VALUES (p_universe_id, v_from, v_to);
      INSERT INTO warps (universe_id, from_sector, to_sector) VALUES (p_universe_id, v_to, v_from);
      v_added := v_added + 1;
      -- update local undirected degrees by +1 for both endpoints
      UPDATE tmp_deg SET deg = deg + 1 WHERE sector_id IN (v_from, v_to);
    EXCEPTION WHEN unique_violation OR check_violation THEN
      CONTINUE;
    END;
  END LOOP;

  SELECT COUNT(*) INTO v_sectors_at_target FROM tmp_deg WHERE deg >= p_target_min;

  RETURN jsonb_build_object(
    'ok', true,
    'links_added', v_added,
    'attempts', v_attempts,
    'sectors_at_target', v_sectors_at_target
  );
END;
$$;


ALTER FUNCTION "public"."densify_universe_links"("p_universe_id" "uuid", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."densify_universe_links_by_id"("p_universe_id" "uuid", "p_target_min" integer DEFAULT 8, "p_max_per_sector" integer DEFAULT 15, "p_max_attempts" integer DEFAULT 200000) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN public.densify_universe_links(p_universe_id, p_target_min, p_max_per_sector, p_max_attempts);
END;
$$;


ALTER FUNCTION "public"."densify_universe_links_by_id"("p_universe_id" "uuid", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."densify_universe_links_by_name"("p_universe_name" "text", "p_target_min" integer DEFAULT 8, "p_max_per_sector" integer DEFAULT 15, "p_max_attempts" integer DEFAULT 200000) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_id uuid;
  v_trim text := trim(p_universe_name);
  v_uuid uuid;
BEGIN
  -- Try UUID parse first
  BEGIN
    v_uuid := v_trim::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_uuid := NULL;
  END;

  IF v_uuid IS NOT NULL THEN
    SELECT id INTO v_id FROM universes WHERE id = v_uuid;
  END IF;

  -- Fallback to case-insensitive name match
  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM universes WHERE name ILIKE v_trim LIMIT 1;
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('error','universe_not_found','input',p_universe_name);
  END IF;

  RETURN public.densify_universe_links(v_id, p_target_min, p_max_per_sector, p_max_attempts);
END;
$$;


ALTER FUNCTION "public"."densify_universe_links_by_name"("p_universe_name" "text", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."deploy_mines"("p_player_id" "uuid", "p_sector_id" "uuid", "p_universe_id" "uuid", "p_torpedoes_to_use" integer DEFAULT 1) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_sector RECORD;
    v_mine_id uuid;
    v_damage_potential integer;
BEGIN
    -- Get player data
    SELECT * INTO v_player
    FROM public.players
    WHERE id = p_player_id AND universe_id = p_universe_id;

    -- Get ship data
    SELECT * INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Player or ship not found');
    END IF;
    
    -- Check if player has enough torpedoes
    IF v_ship.torpedoes < p_torpedoes_to_use THEN
        RETURN jsonb_build_object('error', 'Not enough torpedoes');
    END IF;
    
    -- Get sector info
    SELECT * INTO v_sector
    FROM public.sectors
    WHERE id = p_sector_id AND universe_id = p_universe_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Sector not found');
    END IF;
    
    -- Calculate damage potential based on torpedoes used
    v_damage_potential := p_torpedoes_to_use * 100;
    
    -- Create the mine
    INSERT INTO public.mines (
        sector_id,
        universe_id,
        deployed_by,
        torpedoes_used,
        damage_potential
    ) VALUES (
        p_sector_id,
        p_universe_id,
        p_player_id,
        p_torpedoes_to_use,
        v_damage_potential
    ) RETURNING id INTO v_mine_id;
    
    -- Remove torpedoes from ship
    UPDATE public.ships 
    SET torpedoes = torpedoes - p_torpedoes_to_use
    WHERE player_id = p_player_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'mine_id', v_mine_id,
        'torpedoes_used', p_torpedoes_to_use,
        'damage_potential', v_damage_potential,
        'sector_number', v_sector.number,
        'torpedoes_remaining', v_ship.torpedoes - p_torpedoes_to_use
    );
END;
$$;


ALTER FUNCTION "public"."deploy_mines"("p_player_id" "uuid", "p_sector_id" "uuid", "p_universe_id" "uuid", "p_torpedoes_to_use" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."destroy_universe"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_universe_name TEXT;
  v_player_count INTEGER;
  v_ship_count INTEGER;
  v_planet_count INTEGER;
  v_port_count INTEGER;
  v_sector_count INTEGER;
BEGIN
  -- Get universe name for logging
  SELECT name INTO v_universe_name FROM universes WHERE id = p_universe_id;
  
  IF v_universe_name IS NULL THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_not_found', 'message', 'Universe not found'));
  END IF;
  
  -- Count affected entities
  SELECT COUNT(*) INTO v_player_count FROM players WHERE universe_id = p_universe_id;
  SELECT COUNT(*) INTO v_ship_count FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
  SELECT COUNT(*) INTO v_planet_count FROM planets WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  SELECT COUNT(*) INTO v_port_count FROM ports WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
  SELECT COUNT(*) INTO v_sector_count FROM sectors WHERE universe_id = p_universe_id;
  
  BEGIN
    -- Delete only from tables we know exist and have the right structure
    -- Core game tables first
    
    -- Delete planets (uses sector_id)
    DELETE FROM planets WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    
    -- Delete ports (uses sector_id) 
    DELETE FROM ports WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    
    -- Delete ships (uses player_id)
    DELETE FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
    
    -- Delete players (has universe_id)
    DELETE FROM players WHERE universe_id = p_universe_id;
    
    -- Delete warps (has universe_id)
    DELETE FROM warps WHERE universe_id = p_universe_id;
    
    -- Delete sectors (has universe_id)
    DELETE FROM sectors WHERE universe_id = p_universe_id;
    
    -- Finally, delete the universe itself
    DELETE FROM universes WHERE id = p_universe_id;
    
  EXCEPTION
    WHEN OTHERS THEN
      RETURN jsonb_build_object(
        'error', jsonb_build_object(
          'code', 'destroy_failed',
          'message', 'Failed to destroy universe: ' || SQLERRM
        )
      );
  END;
  
  -- Return success with statistics
  RETURN jsonb_build_object(
    'success', true,
    'universe_name', v_universe_name,
    'universe_id', p_universe_id,
    'statistics', jsonb_build_object(
      'players_deleted', v_player_count,
      'ships_deleted', v_ship_count,
      'planets_deleted', v_planet_count,
      'ports_deleted', v_port_count,
      'sectors_deleted', v_sector_count
    ),
    'message', 'Universe destroyed successfully'
  );
END;
$$;


ALTER FUNCTION "public"."destroy_universe"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."diagnose_ai_players"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_total_players int;
  v_ai_players int;
  v_ai_with_turns int;
  v_sample_player jsonb;
BEGIN
  -- Count total players
  SELECT COUNT(*) INTO v_total_players
  FROM public.players p
  WHERE p.universe_id = p_universe_id;
  
  -- Count AI players
  SELECT COUNT(*) INTO v_ai_players
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  -- Count AI players with turns
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  -- Get sample AI player data
  SELECT jsonb_build_object(
    'id', p.id,
    'handle', p.handle,
    'turns', p.turns,
    'is_ai', p.is_ai,
    'universe_id', p.universe_id,
    'credits', s.credits,
    'hull', s.hull
  ) INTO v_sample_player
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true
  LIMIT 1;
  
  RETURN jsonb_build_object(
    'universe_id', p_universe_id,
    'total_players', v_total_players,
    'ai_players', v_ai_players,
    'ai_with_turns', v_ai_with_turns,
    'sample_player', COALESCE(v_sample_player, jsonb_build_object('status', 'no_ai_players_found'))
  );
END;
$$;


ALTER FUNCTION "public"."diagnose_ai_players"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."emergency_warp"("p_player_id" "uuid", "p_universe_id" "uuid", "p_target_sector_number" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_current_sector RECORD;
    v_target_sector RECORD;
    v_avg_tech numeric;
    v_degradation_threshold numeric;
    v_degradation_applied boolean := false;
    v_hull_damage integer := 0;
    v_random_sector RECORD;
    v_result jsonb;
BEGIN
    -- Get player data
    SELECT * INTO v_player
    FROM public.players
    WHERE id = p_player_id AND universe_id = p_universe_id;
    
    -- Get ship data
    SELECT * INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Player or ship not found');
    END IF;
    
    -- Check if ship has emergency warp device
    IF NOT v_ship.device_emergency_warp THEN
        RETURN jsonb_build_object('error', 'Emergency warp device not installed');
    END IF;
    
    -- Get current sector info
    SELECT * INTO v_current_sector
    FROM public.sectors
    WHERE id = v_player.current_sector;
    
    -- Determine target sector
    IF p_target_sector_number IS NOT NULL THEN
        -- Specific target sector
        SELECT * INTO v_target_sector
        FROM public.sectors
        WHERE number = p_target_sector_number AND universe_id = p_universe_id;
        
        IF NOT FOUND THEN
            RETURN jsonb_build_object('error', 'Target sector not found');
        END IF;
    ELSE
        -- Random sector (emergency escape)
        SELECT * INTO v_random_sector
        FROM public.sectors
        WHERE universe_id = p_universe_id
          AND id != v_player.current_sector
        ORDER BY RANDOM()
        LIMIT 1;
        
        IF NOT FOUND THEN
            RETURN jsonb_build_object('error', 'No sectors available for emergency warp');
        END IF;
        
        v_target_sector := v_random_sector;
    END IF;
    
    -- Calculate average tech level
    v_avg_tech := public.calculate_ship_avg_tech_level(p_player_id);
    
    -- Get degradation threshold from universe settings
    SELECT avg_tech_level_emergency_warp_degrades INTO v_degradation_threshold
    FROM public.universe_settings
    WHERE universe_id = p_universe_id;
    
    -- Default threshold if not set
    IF v_degradation_threshold IS NULL THEN
        v_degradation_threshold := 13;
    END IF;
    
    -- Check if degradation should be applied
    IF v_avg_tech >= v_degradation_threshold THEN
        v_degradation_applied := true;
        -- Calculate hull damage based on tech level (higher tech = more damage)
        v_hull_damage := GREATEST(1, FLOOR((v_avg_tech - v_degradation_threshold) * 2));
        
        -- Apply hull damage
        UPDATE public.ships 
        SET hull = GREATEST(0, hull - v_hull_damage)
        WHERE player_id = p_player_id;
    END IF;
    
    -- Move player to target sector
    UPDATE public.players 
    SET current_sector = v_target_sector.id
    WHERE id = p_player_id;
    
    -- Record the emergency warp event (if table exists)
    BEGIN
        INSERT INTO public.emergency_warp_events (
            player_id,
            universe_id,
            from_sector_id,
            to_sector_id,
            avg_tech_level_at_use,
            degradation_applied,
            hull_damage_taken
        ) VALUES (
            p_player_id,
            p_universe_id,
            v_current_sector.id,
            v_target_sector.id,
            v_avg_tech,
            v_degradation_applied,
            v_hull_damage
        );
    EXCEPTION
        WHEN undefined_table THEN
            -- Table doesn't exist, skip logging
            NULL;
    END;
    
    -- Build result
    v_result := jsonb_build_object(
        'success', true,
        'message', 'Emergency warp successful',
        'from_sector', v_current_sector.number,
        'to_sector', v_target_sector.number,
        'avg_tech_level', v_avg_tech,
        'degradation_threshold', v_degradation_threshold,
        'degradation_applied', v_degradation_applied,
        'hull_damage_taken', v_hull_damage,
        'hull_remaining', v_ship.hull - v_hull_damage
    );
    
    RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."emergency_warp"("p_player_id" "uuid", "p_universe_id" "uuid", "p_target_sector_number" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."execute_trade_route"("p_user_id" "uuid", "p_route_id" "uuid", "p_max_iterations" integer DEFAULT 1, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_player RECORD;
    v_route RECORD;
    v_execution_id UUID;
    v_start_port RECORD;
    v_target_port RECORD;
    v_trade_result JSONB;
    v_move_result JSON;
    v_log TEXT := '';
    v_turns_spent INTEGER := 0;
    v_total_profit BIGINT := 0;
    v_turns_before INTEGER;
    v_turns_after INTEGER;
    v_credits_before NUMERIC;
    v_credits_after NUMERIC;
    v_movement_type TEXT;
    v_distance INTEGER;
    v_engine_level INTEGER;
BEGIN
    -- Get player info with ship engine level (filter by universe if provided)
    IF p_universe_id IS NOT NULL THEN
        SELECT p.*, s.engine_lvl
        INTO v_player
        FROM players p
        JOIN ships s ON p.id = s.player_id
        WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
    ELSE
        SELECT p.*, s.engine_lvl
        INTO v_player
        FROM players p
        JOIN ships s ON p.id = s.player_id
        WHERE p.user_id = p_user_id;
    END IF;

    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
    END IF;

    v_player_id := v_player.id;
    v_turns_before := v_player.turns;

    -- Credits are on ships now
    SELECT credits INTO v_credits_before FROM ships WHERE player_id = v_player_id;

    v_engine_level := v_player.engine_lvl;

    -- Get route info including movement_type
    SELECT tr.* INTO v_route
    FROM trade_routes tr
    WHERE tr.id = p_route_id AND tr.player_id = v_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'route_not_found', 'message', 'Route not found'));
    END IF;

    -- Get waypoints (should be 2: start and target)
    SELECT rw.*, p.id as port_id, p.kind as port_kind, p.sector_id, s.number as sector_number
    INTO v_start_port
    FROM route_waypoints rw
    JOIN ports p ON rw.port_id = p.id
    JOIN sectors s ON p.sector_id = s.id
    WHERE rw.route_id = p_route_id
    ORDER BY rw.sequence_order
    LIMIT 1;

    SELECT rw.*, p.id as port_id, p.kind as port_kind, p.sector_id, s.number as sector_number
    INTO v_target_port
    FROM route_waypoints rw
    JOIN ports p ON rw.port_id = p.id
    JOIN sectors s ON p.sector_id = s.id
    WHERE rw.route_id = p_route_id
    ORDER BY rw.sequence_order
    OFFSET 1
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'no_waypoints', 'message', 'Route needs 2 waypoints'));
    END IF;

    -- Get movement type from route (default to warp if not set)
    v_movement_type := COALESCE(v_route.movement_type, 'warp');
    v_distance := ABS(v_target_port.sector_number - v_start_port.sector_number);

    v_log := 'Starting trade route execution' || E'\n';
    v_log := v_log || 'Start port: Sector ' || v_start_port.sector_number || ' (' || v_start_port.port_kind || ')' || E'\n';
    v_log := v_log || 'Target port: Sector ' || v_target_port.sector_number || ' (' || v_target_port.port_kind || ')' || E'\n';
    v_log := v_log || 'Movement type: ' || v_movement_type || E'\n';
    v_log := v_log || 'Initial state - Turns: ' || v_turns_before || ', Credits: ' || v_credits_before || E'\n';

    -- Calculate required turns based on movement type (include start trade if applicable)
    DECLARE
        v_required_turns INTEGER;
    BEGIN
        IF v_movement_type = 'warp' THEN
            v_required_turns := 3; -- 1 move to target + 1 trade at target + 1 move back
        ELSE -- realspace
            v_required_turns := (v_distance * 2) + 1; -- distance turns each way + 1 trade at target
        END IF;
        -- If the player starts at the start port and we will trade there, add 1 more turn
        IF v_player.current_sector = v_start_port.sector_id THEN
            v_required_turns := v_required_turns + 1;
        END IF;

        IF v_player.turns < v_required_turns THEN
            RETURN json_build_object('error', json_build_object('code', 'insufficient_turns', 'message', 'Need at least ' || v_required_turns || ' turns'));
        END IF;
    END;

    -- Create execution record
    INSERT INTO route_executions (route_id, player_id, status, started_at)
    VALUES (p_route_id, v_player_id, 'running', now())
    RETURNING id INTO v_execution_id;

    -- STEP 1: Trade at start port (if player is there)
    IF v_player.current_sector = v_start_port.sector_id THEN
        v_log := v_log || 'Trading at start port...' || E'\n';

        SELECT game_trade_auto(p_user_id, v_start_port.port_id, p_universe_id) INTO v_trade_result;

        v_log := v_log || 'Start trade result: ' || v_trade_result::text || E'\n';

        IF (v_trade_result->>'ok')::boolean = true THEN
            v_turns_spent := v_turns_spent + 1;
            -- Deduct 1 turn for the successful trade at start port
            UPDATE players SET turns = GREATEST(0, turns - 1) WHERE id = v_player_id;
            v_log := v_log || 'Start port trade successful (1 turn spent)' || E'\n';
        ELSE
            v_log := v_log || 'Start port trade failed: ' || (v_trade_result->>'message') || E'\n';
        END IF;
    ELSE
        v_log := v_log || 'Not at start port, skipping start trade' || E'\n';
    END IF;

    -- STEP 2: Move to target port using correct movement function
    v_log := v_log || 'Moving to target port using ' || v_movement_type || '...' || E'\n';

    IF v_movement_type = 'warp' THEN
        SELECT game_move(p_user_id, v_target_port.sector_number, p_universe_id) INTO v_move_result;
    ELSE -- realspace
        SELECT game_hyperspace(p_user_id, v_target_port.sector_number, p_universe_id) INTO v_move_result;
    END IF;

    v_log := v_log || 'Move result: ' || v_move_result::text || E'\n';

    -- Check if move failed (either ok=false or error field exists)
    IF (v_move_result->>'ok')::boolean = false OR (v_move_result::jsonb) ? 'error' THEN
        v_log := v_log || 'Move failed: ' || COALESCE(v_move_result->>'message', v_move_result->>'error', 'Unknown error');
        UPDATE route_executions SET status = 'failed', error_message = v_log, completed_at = now() WHERE id = v_execution_id;
        RETURN json_build_object('error', json_build_object('code', 'move_failed', 'message', v_log));
    END IF;

    v_turns_spent := v_turns_spent + 1;
    -- Deduct 1 turn for the successful move to target
    UPDATE players SET turns = GREATEST(0, turns - 1) WHERE id = v_player_id;
    v_log := v_log || 'Moved to target port (1 turn spent)' || E'\n';

    -- STEP 3: Trade at target port
    v_log := v_log || 'Trading at target port...' || E'\n';

    SELECT game_trade_auto(p_user_id, v_target_port.port_id, p_universe_id) INTO v_trade_result;

    v_log := v_log || 'Target trade result: ' || v_trade_result::text || E'\n';

    -- Check if trade failed (either ok=false or error field exists)
    IF (v_trade_result->>'ok')::boolean = false OR (v_trade_result::jsonb) ? 'error' THEN
        v_log := v_log || 'Target port trade failed: ' || COALESCE(v_trade_result->>'message', v_trade_result->'error'->>'message', 'Unknown error');
        UPDATE route_executions SET status = 'failed', error_message = v_log, completed_at = now() WHERE id = v_execution_id;
        RETURN json_build_object('error', json_build_object('code', 'trade_failed', 'message', v_log));
    END IF;

    v_turns_spent := v_turns_spent + 1;
    -- Deduct 1 turn for the successful trade at target port
    UPDATE players SET turns = GREATEST(0, turns - 1) WHERE id = v_player_id;
    v_log := v_log || 'Target port trade successful (1 turn spent)' || E'\n';

    -- STEP 4: Move back to start port using correct movement function
    v_log := v_log || 'Moving back to start port using ' || v_movement_type || '...' || E'\n';

    IF v_movement_type = 'warp' THEN
        SELECT game_move(p_user_id, v_start_port.sector_number, p_universe_id) INTO v_move_result;
    ELSE -- realspace
        SELECT game_hyperspace(p_user_id, v_start_port.sector_number, p_universe_id) INTO v_move_result;
    END IF;

    v_log := v_log || 'Return move result: ' || v_move_result::text || E'\n';

    -- Check if return move failed (either ok=false or error field exists)
    IF (v_move_result->>'ok')::boolean = false OR (v_move_result::jsonb) ? 'error' THEN
        v_log := v_log || 'Return move failed: ' || COALESCE(v_move_result->>'message', v_move_result->>'error', 'Unknown error');
        UPDATE route_executions SET status = 'failed', error_message = v_log, completed_at = now() WHERE id = v_execution_id;
        RETURN json_build_object('error', json_build_object('code', 'return_failed', 'message', v_log));
    END IF;

    v_turns_spent := v_turns_spent + 1;
    -- Deduct 1 turn for the successful return move
    UPDATE players SET turns = GREATEST(0, turns - 1) WHERE id = v_player_id;
    v_log := v_log || 'Returned to start port (1 turn spent)' || E'\n';

    -- Get final player turns and ship credits
    SELECT turns INTO v_turns_after FROM players WHERE id = v_player_id;
    SELECT credits INTO v_credits_after FROM ships WHERE player_id = v_player_id;

    v_log := v_log || 'Final state - Turns: ' || v_turns_after || ' (was ' || v_turns_before || '), Credits: ' || v_credits_after || ' (was ' || v_credits_before || ')' || E'\n';
    v_log := v_log || 'Trade route completed! Total turns: ' || v_turns_spent || E'\n';

    -- Update execution record
    UPDATE route_executions 
    SET 
        status = 'completed',
        total_profit = v_total_profit,
        turns_spent = v_turns_spent,
        completed_at = now(),
        execution_data = json_build_object('log', v_log)
    WHERE id = v_execution_id;

    -- Increment player's cumulative turns_spent for leaderboard/analytics (best-effort)
    BEGIN
        PERFORM public.track_turn_spent(v_player_id, v_turns_spent, 'execute_trade_route');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'track_turn_spent not available or failed: %', SQLERRM;
    END;

    -- Update route
    UPDATE trade_routes 
    SET last_executed_at = now(), updated_at = now()
    WHERE id = p_route_id;

    RETURN json_build_object(
        'ok', true,
        'execution_id', v_execution_id,
        'total_profit', v_total_profit,
        'turns_spent', v_turns_spent,
        'log', v_log,
        'message', 'Trade route completed successfully'
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', json_build_object('code','internal_error','message','Internal server error: ' || SQLERRM));
END;
$$;


ALTER FUNCTION "public"."execute_trade_route"("p_user_id" "uuid", "p_route_id" "uuid", "p_max_iterations" integer, "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_engine_upgrade"("p_user_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id UUID;
  v_ship_credits BIGINT;
  v_engine_lvl INT;
  v_cost INT;
BEGIN
  -- Get player and ship data
  SELECT p.id, s.credits INTO v_player_id, v_ship_credits 
  FROM players p 
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  SELECT engine_lvl INTO v_engine_lvl FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  v_cost := 500 * (v_engine_lvl + 1);
  IF v_ship_credits < v_cost THEN
    RETURN json_build_object('error', json_build_object('code','insufficient_funds','message','Insufficient credits'));
  END IF;

  -- Update ship credits and engine level
  UPDATE ships SET 
    credits = credits - v_cost,
    engine_lvl = engine_lvl + 1 
  WHERE player_id = v_player_id;

  -- Return success with updated values
  SELECT credits, engine_lvl INTO v_ship_credits, v_engine_lvl
  FROM ships
  WHERE player_id = v_player_id;

  RETURN json_build_object(
    'success', true,
    'credits', v_ship_credits,
    'engine_lvl', v_engine_lvl,
    'cost', v_cost
  );
END;
$$;


ALTER FUNCTION "public"."game_engine_upgrade"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_hyperspace"("p_id" "uuid", "p_target_sector_number" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_user_id uuid;
  v_universe_id uuid;
BEGIN
  -- Treat p_id as player_id first
  SELECT user_id, universe_id
    INTO v_user_id, v_universe_id
  FROM public.players
  WHERE id = p_id
  LIMIT 1;

  -- If not a player_id, treat p_id as user_id
  IF v_user_id IS NULL THEN
    SELECT user_id, universe_id
      INTO v_user_id, v_universe_id
    FROM public.players
    WHERE user_id = p_id
    LIMIT 1;
  END IF;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'user_or_player_not_found');
  END IF;

  IF v_universe_id IS NULL THEN
    SELECT universe_id INTO v_universe_id
    FROM public.players
    WHERE user_id = v_user_id
    LIMIT 1;
  END IF;

  RETURN public.game_hyperspace(v_user_id, p_target_sector_number, v_universe_id);
END;
$$;


ALTER FUNCTION "public"."game_hyperspace"("p_id" "uuid", "p_target_sector_number" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id UUID;
  v_turns INT;
  v_current_sector_id UUID;
  v_current_number INT;
  v_target_sector_id UUID;
  v_engine_lvl INT;
  v_cost INT;
BEGIN
  -- Load player, current sector, ship - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT p.id, p.turns, p.current_sector
    INTO v_player_id, v_turns, v_current_sector_id
    FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
  ELSE
    SELECT p.id, p.turns, p.current_sector
    INTO v_player_id, v_turns, v_current_sector_id
    FROM players p WHERE p.user_id = p_user_id;
  END IF;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  SELECT s.number INTO v_current_number FROM sectors s WHERE s.id = v_current_sector_id;

  -- Get target sector - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT id INTO v_target_sector_id 
    FROM sectors 
    WHERE number = p_target_sector_number AND universe_id = p_universe_id;
  ELSE
    SELECT id INTO v_target_sector_id 
    FROM sectors 
    WHERE number = p_target_sector_number;
  END IF;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Target sector not found'));
  END IF;

  -- Get engine level
  SELECT engine_lvl INTO v_engine_lvl FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  -- Calculate cost
  -- At engine level 15+, cost is 1 turn for any distance; scales based on distance at lower levels
  IF v_engine_lvl >= 15 THEN
    v_cost := 1;
  ELSE
    v_cost := GREATEST(1, CEIL(ABS(p_target_sector_number - v_current_number) / GREATEST(1, v_engine_lvl)));
  END IF;

  -- Check turns
  IF v_turns < v_cost THEN
    RETURN json_build_object('error', json_build_object('code','insufficient_turns','message','Not enough turns'));
  END IF;

  -- Perform jump
  UPDATE players SET 
    current_sector = v_target_sector_id,
    turns = turns - v_cost
  WHERE id = v_player_id;

  -- Return success
  RETURN json_build_object(
    'ok', true,
    'message', 'Hyperspace jump successful',
    'cost', v_cost,
    'player', json_build_object(
      'id', v_player_id,
      'turns', v_turns - v_cost,
      'current_sector', v_target_sector_id,
      'current_sector_number', p_target_sector_number
    )
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', json_build_object('code','server_error','message','Hyperspace operation failed: ' || SQLERRM));
END;
$$;


ALTER FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer, "p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_player_id uuid;
  v_current_sector_id uuid;
  v_target_sector_id uuid;
  v_turns integer;
  v_exists boolean;
BEGIN
  -- Get player in universe
  SELECT id, current_sector, turns
    INTO v_player_id, v_current_sector_id, v_turns
  FROM public.players
  WHERE user_id = p_user_id AND universe_id = p_universe_id
  LIMIT 1;

  IF v_player_id IS NULL THEN
    RETURN jsonb_build_object('error', 'player_not_found');
  END IF;

  -- Validate target sector exists in same universe
  SELECT id INTO v_target_sector_id
  FROM public.sectors
  WHERE universe_id = p_universe_id AND number = p_to_sector_number
  LIMIT 1;

  IF v_target_sector_id IS NULL THEN
    RETURN jsonb_build_object('error', 'target_sector_not_found');
  END IF;

  -- Check warp connectivity using sector UUIDs
  SELECT EXISTS (
    SELECT 1 FROM public.warps
    WHERE universe_id = p_universe_id
      AND from_sector = v_current_sector_id
      AND to_sector = v_target_sector_id
  ) INTO v_exists;

  IF NOT v_exists THEN
    RETURN jsonb_build_object('error', 'no_warp_connection');
  END IF;

  -- Ensure at least 1 turn
  IF COALESCE(v_turns, 0) < 1 THEN
    RETURN jsonb_build_object('error', 'insufficient_turns');
  END IF;

  -- Perform move: decrement turns and set sector
  UPDATE public.players
  SET current_sector = v_target_sector_id,
      turns = v_turns - 1
  WHERE id = v_player_id;

  -- Mandatory turn tracking
  PERFORM public.track_turn_spent(v_player_id);

  -- Return success with new sector number
  RETURN jsonb_build_object(
    'ok', true,
    'to', p_to_sector_number
  );
END;
$$;


ALTER FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer, "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text" DEFAULT 'Colony'::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_sector_id UUID;
    v_universe_id UUID;
    v_planet_id UUID;
BEGIN
    -- Find player by auth user_id
    SELECT p.id, s.universe_id
    INTO v_player_id, v_universe_id
    FROM players p
    JOIN sectors s ON p.current_sector = s.id
    WHERE p.user_id = p_user_id;

    IF v_player_id IS NULL THEN
        RAISE EXCEPTION 'player_not_found' USING ERRCODE = 'P0001';
    END IF;

    -- Resolve target sector id in same universe
    SELECT id INTO v_sector_id FROM sectors WHERE universe_id = v_universe_id AND number = p_sector_number;
    IF v_sector_id IS NULL THEN
        RAISE EXCEPTION 'invalid_sector' USING ERRCODE = 'P0001';
    END IF;

    -- Must be in that sector
    IF NOT EXISTS (
        SELECT 1 FROM players p WHERE p.id = v_player_id AND p.current_sector = v_sector_id
    ) THEN
        RAISE EXCEPTION 'not_in_sector' USING ERRCODE = 'P0001';
    END IF;

    -- Sector must have a pre-generated unowned planet
    SELECT id INTO v_planet_id FROM planets WHERE sector_id = v_sector_id;
    IF v_planet_id IS NULL THEN
        RAISE EXCEPTION 'no_planet_in_sector' USING ERRCODE = 'P0001';
    END IF;

    -- Claim only if unowned
    UPDATE planets
    SET owner_player_id = v_player_id,
        name = COALESCE(NULLIF(TRIM(p_name), ''), 'Colony')
    WHERE id = v_planet_id AND owner_player_id IS NULL;

    -- Ensure we actually claimed it
    IF (SELECT owner_player_id FROM planets WHERE id = v_planet_id) IS DISTINCT FROM v_player_id THEN
        RAISE EXCEPTION 'planet_already_owned' USING ERRCODE = 'P0001';
    END IF;

    RETURN json_build_object(
        'planet_id', v_planet_id,
        'name', p_name,
        'sector_number', p_sector_number
    );
END;
$$;


ALTER FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text" DEFAULT 'Colony'::"text", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id UUID;
  v_sector_id UUID;
  v_universe_id UUID;
  v_planet_id UUID;
BEGIN
  -- Find player by auth user_id - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT p.id, p.universe_id
    INTO v_player_id, v_universe_id
    FROM public.players p
    WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
  ELSE
    SELECT p.id, p.universe_id
    INTO v_player_id, v_universe_id
    FROM public.players p
    WHERE p.user_id = p_user_id;
  END IF;

  IF v_player_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Player not found'
    );
  END IF;

  -- Resolve target sector id in same universe
  SELECT id INTO v_sector_id 
  FROM public.sectors 
  WHERE number = p_sector_number AND universe_id = v_universe_id;

  IF v_sector_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Sector not found in your universe'
    );
  END IF;

  -- Check if planet exists in this sector
  SELECT id INTO v_planet_id 
  FROM public.planets 
  WHERE sector_id = v_sector_id AND owner_player_id IS NULL;

  IF v_planet_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'No unowned planet found in this sector'
    );
  END IF;

  -- Check if player has enough credits and turns
  IF NOT EXISTS (
    SELECT 1 FROM public.ships s 
    WHERE s.player_id = v_player_id 
    AND s.credits >= 10000
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Insufficient credits (need 10,000)'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.players p 
    WHERE p.id = v_player_id 
    AND p.turns >= 5
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Insufficient turns (need 5)'
    );
  END IF;

  -- Claim the planet
  UPDATE public.planets 
  SET 
    owner_player_id = v_player_id,
    name = p_name,
    colonists = 1000,
    ore = 0,
    organics = 0,
    goods = 0,
    energy = 0,
    fighters = 0,
    torpedoes = 0,
    credits = 0,
    production_ore_percent = 0,
    production_organics_percent = 0,
    production_goods_percent = 0,
    production_energy_percent = 0,
    production_fighters_percent = 0,
    production_torpedoes_percent = 0,
    base_built = false
  WHERE id = v_planet_id;

  -- Deduct credits and turns
  UPDATE public.ships 
  SET credits = credits - 10000 
  WHERE player_id = v_player_id;

  UPDATE public.players 
  SET turns = turns - 5 
  WHERE id = v_player_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Planet claimed successfully',
    'planet_id', v_planet_id,
    'planet_name', p_name,
    'credits_deducted', 10000,
    'turns_deducted', 5
  );
END;
$$;


ALTER FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_planet_store"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id uuid;
  v_player_ship_id uuid;
  v_planet_record planets;
  v_ship_record ships;
  v_field text;
  v_current_ship_qty integer;
  v_result json;
BEGIN
  -- Get player and ship info
  SELECT p.id, s.id INTO v_player_id, v_player_ship_id
  FROM players p
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
  END IF;
  
  -- Get planet info
  SELECT * INTO v_planet_record
  FROM planets 
  WHERE id = p_planet AND owner_player_id = v_player_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code', 'planet_not_found', 'message', 'Planet not found or not owned by player'));
  END IF;
  
  -- Get ship info
  SELECT * INTO v_ship_record
  FROM ships 
  WHERE id = v_player_ship_id;
  
  -- Validate resource type
  IF p_resource NOT IN ('ore', 'organics', 'goods', 'energy') THEN
    RETURN json_build_object('error', json_build_object('code', 'invalid_resource', 'message', 'Invalid resource type'));
  END IF;
  
  -- Get current ship quantity and planet field
  CASE p_resource
    WHEN 'ore' THEN 
      v_current_ship_qty := v_ship_record.ore;
      v_field := 'ore';
    WHEN 'organics' THEN 
      v_current_ship_qty := v_ship_record.organics;
      v_field := 'organics';
    WHEN 'goods' THEN 
      v_current_ship_qty := v_ship_record.goods;
      v_field := 'goods';
    WHEN 'energy' THEN 
      v_current_ship_qty := v_ship_record.energy;
      v_field := 'energy';
  END CASE;
  
  -- Validate quantity
  IF p_qty <= 0 OR p_qty > v_current_ship_qty THEN
    RETURN json_build_object('error', json_build_object('code', 'invalid_quantity', 'message', 'Invalid quantity'));
  END IF;
  
  -- Update planet and ship
  EXECUTE format('UPDATE planets SET %I = %I + %s WHERE id = %L', v_field, v_field, p_qty, p_planet);
  EXECUTE format('UPDATE ships SET %I = %I - %s WHERE id = %L', v_field, v_field, p_qty, v_player_ship_id);
  
  RETURN json_build_object(
    'success', true,
    'resource', p_resource,
    'quantity_stored', p_qty,
    'planet_' || p_resource, 
    CASE p_resource
      WHEN 'ore' THEN v_planet_record.ore + p_qty
      WHEN 'organics' THEN v_planet_record.organics + p_qty
      WHEN 'goods' THEN v_planet_record.goods + p_qty
      WHEN 'energy' THEN v_planet_record.energy + p_qty
    END
  );
END;
$$;


ALTER FUNCTION "public"."game_planet_store"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_planet_withdraw"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id uuid;
  v_player_ship_id uuid;
  v_planet_record planets;
  v_ship_record ships;
  v_field text;
  v_current_planet_qty bigint;
  v_ship_cargo integer;
  v_ship_cargo_max integer;
  v_result json;
BEGIN
  -- Get player and ship info
  SELECT p.id, s.id INTO v_player_id, v_player_ship_id
  FROM players p
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
  END IF;
  
  -- Get planet info
  SELECT * INTO v_planet_record
  FROM planets 
  WHERE id = p_planet AND owner_player_id = v_player_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code', 'planet_not_found', 'message', 'Planet not found or not owned by player'));
  END IF;
  
  -- Get ship info
  SELECT * INTO v_ship_record
  FROM ships 
  WHERE id = v_player_ship_id;
  
  -- Validate resource type
  IF p_resource NOT IN ('ore', 'organics', 'goods', 'energy') THEN
    RETURN json_build_object('error', json_build_object('code', 'invalid_resource', 'message', 'Invalid resource type'));
  END IF;
  
  -- Get current planet quantity and ship cargo info
  CASE p_resource
    WHEN 'ore' THEN 
      v_current_planet_qty := v_planet_record.ore;
      v_field := 'ore';
    WHEN 'organics' THEN 
      v_current_planet_qty := v_planet_record.organics;
      v_field := 'organics';
    WHEN 'goods' THEN 
      v_current_planet_qty := v_planet_record.goods;
      v_field := 'goods';
    WHEN 'energy' THEN 
      v_current_planet_qty := v_planet_record.energy;
      v_field := 'energy';
  END CASE;
  
  -- Calculate ship cargo capacity
  v_ship_cargo := v_ship_record.ore + v_ship_record.organics + v_ship_record.goods + v_ship_record.energy + v_ship_record.colonists;
  v_ship_cargo_max := v_ship_record.cargo;
  
  -- Validate quantity
  IF p_qty <= 0 OR p_qty > v_current_planet_qty THEN
    RETURN json_build_object('error', json_build_object('code', 'invalid_quantity', 'message', 'Invalid quantity'));
  END IF;
  
  -- Check ship cargo capacity
  IF (v_ship_cargo + p_qty) > v_ship_cargo_max THEN
    RETURN json_build_object('error', json_build_object('code', 'insufficient_cargo', 'message', 'Not enough ship cargo space'));
  END IF;
  
  -- Update planet and ship
  EXECUTE format('UPDATE planets SET %I = %I - %s WHERE id = %L', v_field, v_field, p_qty, p_planet);
  EXECUTE format('UPDATE ships SET %I = %I + %s WHERE id = %L', v_field, v_field, p_qty, v_player_ship_id);
  
  RETURN json_build_object(
    'success', true,
    'resource', p_resource,
    'quantity_withdrawn', p_qty,
    'planet_' || p_resource, 
    CASE p_resource
      WHEN 'ore' THEN v_planet_record.ore - p_qty
      WHEN 'organics' THEN v_planet_record.organics - p_qty
      WHEN 'goods' THEN v_planet_record.goods - p_qty
      WHEN 'energy' THEN v_planet_record.energy - p_qty
    END
  );
END;
$$;


ALTER FUNCTION "public"."game_planet_withdraw"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_repair"("p_user_id" "uuid", "p_hull" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id UUID;
  v_ship_credits BIGINT;
  v_current_sector UUID;
  v_port_id UUID;
  v_ship_id UUID;
  v_current_hull INTEGER;
  v_hull_max INTEGER := 100;
  v_hull_repair_cost INTEGER := 2;
  v_actual_repair INTEGER;
  v_total_cost INTEGER;
  v_result JSON;
BEGIN
  IF p_hull <= 0 THEN
    RETURN json_build_object('error', 'Repair amount must be positive');
  END IF;
  
  -- Get player and ship data
  SELECT p.id, s.credits, p.current_sector, s.id
  INTO v_player_id, v_ship_credits, v_current_sector, v_ship_id
  FROM players p 
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Player not found');
  END IF;

  -- Check if player is at a port
  SELECT id INTO v_port_id FROM ports WHERE sector_id = v_current_sector;
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Must be at a port to repair');
  END IF;

  -- Get current hull
  SELECT hull INTO v_current_hull FROM ships WHERE id = v_ship_id;
  
  -- Calculate actual repair needed
  v_actual_repair := LEAST(p_hull, v_hull_max - v_current_hull);
  v_total_cost := v_actual_repair * v_hull_repair_cost;
  
  -- Check if player has enough credits
  IF v_ship_credits < v_total_cost THEN
    RETURN json_build_object('error', 'Insufficient credits');
  END IF;
  
  -- Perform repair
  UPDATE ships SET 
    hull = hull + v_actual_repair,
    credits = credits - v_total_cost
  WHERE id = v_ship_id;
  
  -- Return success
  RETURN json_build_object(
    'success', true,
    'repaired', v_actual_repair,
    'cost', v_total_cost,
    'new_hull', v_current_hull + v_actual_repair
  );
END;
$$;


ALTER FUNCTION "public"."game_repair"("p_user_id" "uuid", "p_hull" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_ship_rename"("p_user_id" "uuid", "p_name" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_clean_name TEXT;
BEGIN
  -- Get player data
  SELECT p.* INTO v_player
  FROM players p
  WHERE p.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship data
  SELECT s.* INTO v_ship
  FROM ships s
  WHERE s.player_id = v_player.id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  -- Sanitize and validate name
  v_clean_name := TRIM(p_name);
  
  IF LENGTH(v_clean_name) = 0 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_name', 'message', 'Ship name cannot be empty'));
  END IF;

  IF LENGTH(v_clean_name) > 32 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_name', 'message', 'Ship name must be 32 characters or less'));
  END IF;

  -- Update ship name
  UPDATE ships SET name = v_clean_name WHERE player_id = v_player.id;

  -- Return success
  RETURN jsonb_build_object(
    'ok', true,
    'name', v_clean_name
  );
END;
$$;


ALTER FUNCTION "public"."game_ship_rename"("p_user_id" "uuid", "p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_cost INTEGER;
  v_next_level INTEGER;
BEGIN
  -- Validate attribute (current set; future attrs can be added without changing costs)
  IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull', 'power', 'beam', 'torp_launcher', 'armor') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
  END IF;

  -- Get player (optionally universe scoped)
  IF p_universe_id IS NOT NULL THEN
    SELECT p.* INTO v_player FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id FOR UPDATE;
  ELSE
    SELECT p.* INTO v_player FROM players p WHERE p.user_id = p_user_id FOR UPDATE;
  END IF;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship
  SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  -- Must be at Special port
  IF NOT EXISTS (
    SELECT 1 FROM ports p JOIN sectors s ON p.sector_id = s.id
    WHERE s.id = v_player.current_sector AND p.kind = 'special'
  ) THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'wrong_port', 'message', 'Must be at a Special port to upgrade'));
  END IF;

  -- Calculate cost based on attribute (original BNT doubling formula: 1000 * 2^level)
  CASE p_attr
    WHEN 'engine' THEN
      v_cost := 1000 * POWER(2, v_ship.engine_lvl);
    WHEN 'computer' THEN
      v_cost := 1000 * POWER(2, v_ship.comp_lvl);
    WHEN 'sensors' THEN
      v_cost := 1000 * POWER(2, v_ship.sensor_lvl);
    WHEN 'shields' THEN
      v_cost := 1000 * POWER(2, v_ship.shield_lvl);
    WHEN 'hull' THEN
      v_cost := 1000 * POWER(2, v_ship.hull_lvl);
    WHEN 'power' THEN
      v_cost := 1000 * POWER(2, v_ship.power_lvl);
    WHEN 'beam' THEN
      v_cost := 1000 * POWER(2, v_ship.beam_lvl);
    WHEN 'torp_launcher' THEN
      v_cost := 1000 * POWER(2, v_ship.torp_launcher_lvl);
    WHEN 'armor' THEN
      v_cost := 1000 * POWER(2, v_ship.armor_lvl);
  END CASE;

  -- Check if ship has enough credits
  IF v_ship.credits < v_cost THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
  END IF;

  -- Perform upgrade and deduct credits from ship
  CASE p_attr
    WHEN 'engine' THEN 
      UPDATE ships SET engine_lvl = engine_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'computer' THEN 
      UPDATE ships SET comp_lvl = comp_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'sensors' THEN 
      UPDATE ships SET sensor_lvl = sensor_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'shields' THEN 
      -- FIXED: Just upgrade level, shields are calculated dynamically in combat
      UPDATE ships SET shield_lvl = shield_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'hull' THEN 
      UPDATE ships SET 
        hull_lvl = hull_lvl + 1, 
        hull = hull_max, 
        credits = credits - v_cost,
        cargo = FLOOR(100 * POWER(1.5, hull_lvl + 1))
      WHERE player_id = v_player.id;
    WHEN 'power' THEN 
      UPDATE ships SET power_lvl = power_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'beam' THEN 
      UPDATE ships SET beam_lvl = beam_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'torp_launcher' THEN 
      UPDATE ships SET torp_launcher_lvl = torp_launcher_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'armor' THEN 
      UPDATE ships SET armor_lvl = armor_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
  END CASE;

  -- Get updated ship data for response
  SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = v_player.id;

  RETURN jsonb_build_object(
    'ok', true, 
    'attribute', p_attr, 
    'next_level', CASE p_attr
      WHEN 'engine' THEN v_ship.engine_lvl
      WHEN 'computer' THEN v_ship.comp_lvl
      WHEN 'sensors' THEN v_ship.sensor_lvl
      WHEN 'shields' THEN v_ship.shield_lvl
      WHEN 'hull' THEN v_ship.hull_lvl
      WHEN 'power' THEN v_ship.power_lvl
      WHEN 'beam' THEN v_ship.beam_lvl
      WHEN 'torp_launcher' THEN v_ship.torp_launcher_lvl
      WHEN 'armor' THEN v_ship.armor_lvl
    END, 
    'cost', v_cost, 
    'credits_after', v_ship.credits
  );
END;
$$;


ALTER FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") IS 'Upgrades ship attributes at Special Ports. Uses BNT exponential cost formula (1000 * 2^level). Shields are calculated dynamically in combat.';



CREATE OR REPLACE FUNCTION "public"."game_trade"("p_user_id" "uuid", "p_port_id" "uuid", "p_action" "text", "p_resource" "text", "p_qty" integer, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id UUID;
  v_player_current_sector UUID;
  v_ship RECORD;
  v_port RECORD;
  v_unit_price NUMERIC;
  v_total NUMERIC;
  v_cargo_used INTEGER;
  v_cargo_free INTEGER;
  v_energy_free INTEGER;
BEGIN
  -- Validate inputs
  IF p_action NOT IN ('buy','sell') THEN
    RETURN json_build_object('error', json_build_object('code','invalid_action','message','Invalid action'));
  END IF;
  IF p_resource NOT IN ('ore','organics','goods','energy') THEN
    RETURN json_build_object('error', json_build_object('code','invalid_resource','message','Invalid resource'));
  END IF;
  IF p_qty <= 0 THEN
    RETURN json_build_object('error', json_build_object('code','invalid_qty','message','Quantity must be positive'));
  END IF;

  -- Get player info - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT p.id, p.current_sector
    INTO v_player_id, v_player_current_sector
    FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
  ELSE
    SELECT p.id, p.current_sector
    INTO v_player_id, v_player_current_sector
    FROM players p WHERE p.user_id = p_user_id;
  END IF;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
  END IF;

  -- Get ship data (includes credits and inventory)
  SELECT * INTO v_ship FROM ships WHERE player_id = v_player_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
  END IF;

  -- Get port data
  SELECT * INTO v_port FROM ports WHERE id = p_port_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code','not_found','message','Port not found'));
  END IF;

  -- Check if player is in the same sector as the port
  IF v_player_current_sector != v_port.sector_id THEN
    RETURN json_build_object('error', json_build_object('code','wrong_sector','message','You must be in the same sector as the port'));
  END IF;

  -- Calculate unit price based on port type and resource
  CASE p_resource
    WHEN 'ore' THEN
      v_unit_price := v_port.price_ore;
    WHEN 'organics' THEN
      v_unit_price := v_port.price_organics;
    WHEN 'goods' THEN
      v_unit_price := v_port.price_goods;
    WHEN 'energy' THEN
      v_unit_price := v_port.price_energy;
  END CASE;

  v_total := v_unit_price * p_qty;

  -- Handle buy action
  IF p_action = 'buy' THEN
    -- Check if player has enough credits
    IF v_ship.credits < v_total THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_credits','message','Insufficient credits'));
    END IF;

    -- UPDATED: Check capacity based on resource type
    IF p_resource = 'energy' THEN
      -- Energy uses separate capacity (energy_max)
      v_energy_free := v_ship.energy_max - v_ship.energy;
      IF p_qty > v_energy_free THEN
        RETURN json_build_object('error', json_build_object(
          'code','insufficient_energy_capacity',
          'message','Insufficient energy capacity (available: ' || v_energy_free || '). Upgrade Power at a Special Port.'
        ));
      END IF;
    ELSE
      -- Other resources use cargo capacity
      v_cargo_used := v_ship.ore + v_ship.organics + v_ship.goods;
      v_cargo_free := v_ship.cargo - v_cargo_used;
      IF p_qty > v_cargo_free THEN
        RETURN json_build_object('error', json_build_object('code','insufficient_cargo','message','Insufficient cargo space'));
      END IF;
    END IF;

    -- Check if port has enough stock
    CASE p_resource
      WHEN 'ore' THEN
        IF v_port.ore < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
        END IF;
      WHEN 'organics' THEN
        IF v_port.organics < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
        END IF;
      WHEN 'goods' THEN
        IF v_port.goods < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
        END IF;
      WHEN 'energy' THEN
        IF v_port.energy < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
        END IF;
    END CASE;

    -- Execute buy transaction
    UPDATE ships SET 
      credits = credits - v_total,
      ore = CASE WHEN p_resource = 'ore' THEN ore + p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics + p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods + p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy + p_qty ELSE energy END
    WHERE id = v_ship.id;
    
    UPDATE ports SET 
      ore = CASE WHEN p_resource = 'ore' THEN ore - p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics - p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods - p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy - p_qty ELSE energy END
    WHERE id = p_port_id;

  -- Handle sell action
  ELSE
    -- Check if player has enough inventory
    CASE p_resource
      WHEN 'ore' THEN
        IF v_ship.ore < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
        END IF;
      WHEN 'organics' THEN
        IF v_ship.organics < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
        END IF;
      WHEN 'goods' THEN
        IF v_ship.goods < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
        END IF;
      WHEN 'energy' THEN
        IF v_ship.energy < p_qty THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
        END IF;
    END CASE;

    -- Execute sell transaction
    UPDATE ships SET 
      credits = credits + v_total,
      ore = CASE WHEN p_resource = 'ore' THEN ore - p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics - p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods - p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy - p_qty ELSE energy END
    WHERE id = v_ship.id;
    
    UPDATE ports SET 
      ore = CASE WHEN p_resource = 'ore' THEN ore + p_qty ELSE ore END,
      organics = CASE WHEN p_resource = 'organics' THEN organics + p_qty ELSE organics END,
      goods = CASE WHEN p_resource = 'goods' THEN goods + p_qty ELSE goods END,
      energy = CASE WHEN p_resource = 'energy' THEN energy + p_qty ELSE energy END
    WHERE id = p_port_id;
  END IF;

  -- Return success result
  RETURN json_build_object(
    'success', true,
    'message', 'Trade completed successfully',
    'action', p_action,
    'resource', p_resource,
    'quantity', p_qty,
    'unit_price', v_unit_price,
    'total', v_total,
    'ship_credits_after', v_ship.credits + CASE WHEN p_action = 'buy' THEN -v_total ELSE v_total END
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Exception in game_trade: %', SQLERRM;
    RETURN json_build_object('error', json_build_object('code','internal_error','message','Internal server error: ' || SQLERRM));
END;
$$;


ALTER FUNCTION "public"."game_trade"("p_user_id" "uuid", "p_port_id" "uuid", "p_action" "text", "p_resource" "text", "p_qty" integer, "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Simply call the 3-parameter version with NULL universe_id
    RETURN public.game_trade_auto(p_user_id, p_port, NULL);
END;
$$;


ALTER FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_port RECORD;
    pc TEXT; -- port commodity
    sell_price NUMERIC; -- native sell price (0.90 * base)
    proceeds NUMERIC := 0;
    sold_ore INT := 0; sold_organics INT := 0; sold_goods INT := 0; sold_energy INT := 0;
    new_ore INT; new_organics INT; new_goods INT; new_energy INT;
    native_stock INT; native_price NUMERIC;
    credits_after NUMERIC;
    ship_cargo_capacity INT;
    current_cargo INT;
    remaining_cargo INT;
    cargo_after INT; q INT := 0;
    native_key TEXT;
BEGIN
    -- Load player, ship, port - filter by universe if provided
    IF p_universe_id IS NOT NULL THEN
        SELECT * INTO v_player FROM public.players WHERE user_id = p_user_id AND universe_id = p_universe_id FOR UPDATE;
    ELSE
        SELECT * INTO v_player FROM public.players WHERE user_id = p_user_id FOR UPDATE;
    END IF;
    
    IF NOT FOUND THEN 
        RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Player not found')); 
    END IF;

    SELECT * INTO v_ship FROM public.ships WHERE player_id = v_player.id FOR UPDATE;
    IF NOT FOUND THEN 
        RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Ship not found')); 
    END IF;

    SELECT p.*, s.number as sector_number INTO v_port
    FROM public.ports p
    JOIN public.sectors s ON s.id = p.sector_id
    WHERE p.id = p_port FOR UPDATE;
    IF NOT FOUND THEN 
        RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Port not found')); 
    END IF;
    
    IF v_port.kind = 'special' THEN 
        RETURN jsonb_build_object('error', jsonb_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.')); 
    END IF;

    -- Validate co-location
    IF v_player.current_sector <> v_port.sector_id THEN
        RETURN jsonb_build_object('error', jsonb_build_object('code','wrong_sector','message','Player not in port sector'));
    END IF;

    pc := v_port.kind; -- ore|organics|goods|energy
    native_key := pc;

    -- Calculate ship cargo capacity using BNT formula
    ship_cargo_capacity := FLOOR(100 * POWER(1.5, COALESCE(v_ship.hull_lvl, 1)));
    
    -- Get current cargo load
    current_cargo := v_ship.ore + v_ship.organics + v_ship.goods + v_ship.energy;
    remaining_cargo := GREATEST(0, ship_cargo_capacity - current_cargo);

    -- Initialize new quantities with current values
    new_ore := v_ship.ore;
    new_organics := v_ship.organics;
    new_goods := v_ship.goods;
    new_energy := v_ship.energy;

    -- pricing with dynamic stock-based multipliers
    native_price := case pc
        when 'ore' then v_port.price_ore * calculate_price_multiplier(v_port.ore)
        when 'organics' then v_port.price_organics * calculate_price_multiplier(v_port.organics)
        when 'goods' then v_port.price_goods * calculate_price_multiplier(v_port.goods)
        when 'energy' then v_port.price_energy * calculate_price_multiplier(v_port.energy)
    end;
    sell_price := native_price * 0.90; -- sell price (player buys)

    -- Sell all non-native resources first
    if v_ship.ore > 0 and pc <> 'ore' then
        q := v_ship.ore;
        sold_ore := q;
        proceeds := proceeds + (q * v_port.price_ore * calculate_price_multiplier(v_port.ore) * 1.10);
        new_ore := 0;
        v_port.ore := v_port.ore + sold_ore;
    end if;

    if v_ship.organics > 0 and pc <> 'organics' then
        q := v_ship.organics;
        sold_organics := q;
        proceeds := proceeds + (q * v_port.price_organics * calculate_price_multiplier(v_port.organics) * 1.10);
        new_organics := 0;
        v_port.organics := v_port.organics + sold_organics;
    end if;

    if v_ship.goods > 0 and pc <> 'goods' then
        q := v_ship.goods;
        sold_goods := q;
        proceeds := proceeds + (q * v_port.price_goods * calculate_price_multiplier(v_port.goods) * 1.10);
        new_goods := 0;
        v_port.goods := v_port.goods + sold_goods;
    end if;

    if v_ship.energy > 0 and pc <> 'energy' then
        q := v_ship.energy;
        sold_energy := q;
        proceeds := proceeds + (q * v_port.price_energy * calculate_price_multiplier(v_port.energy) * 1.10);
        new_energy := 0;
        v_port.energy := v_port.energy + sold_energy;
    end if;

    -- Update ship credits with proceeds from selling
    UPDATE public.ships SET credits = credits + proceeds WHERE id = v_ship.id;

    -- Get updated ship credits after selling
    SELECT credits INTO credits_after FROM public.ships WHERE id = v_ship.id;

    -- Calculate remaining cargo space after selling
    cargo_after := new_ore + new_organics + new_goods + new_energy;
    remaining_cargo := GREATEST(0, ship_cargo_capacity - cargo_after);

    -- Get native stock
    native_stock := case pc
        when 'ore' then v_port.ore
        when 'organics' then v_port.organics
        when 'goods' then v_port.goods
        when 'energy' then v_port.energy
    end;

    -- Buy native commodity - ALWAYS try to buy if there's space and credits, even with no cargo
    IF remaining_cargo > 0 AND native_stock > 0 AND credits_after > 0 THEN
        -- Calculate how much we can afford and fit
        q := LEAST(
            FLOOR(credits_after / sell_price),  -- What we can afford
            native_stock,                       -- What port has
            remaining_cargo                     -- What fits in cargo
        );
        
        IF q > 0 THEN
            -- Update ship inventory with native commodity
            CASE pc
                WHEN 'ore' THEN
                    new_ore := new_ore + q;
                    v_port.ore := v_port.ore - q;
                WHEN 'organics' THEN
                    new_organics := new_organics + q;
                    v_port.organics := v_port.organics - q;
                WHEN 'goods' THEN
                    new_goods := new_goods + q;
                    v_port.goods := v_port.goods - q;
                WHEN 'energy' THEN
                    new_energy := new_energy + q;
                    v_port.energy := v_port.energy - q;
            END CASE;
            
            -- Deduct cost from ship credits
            UPDATE public.ships SET 
                credits = credits - (q * sell_price),
                ore = new_ore,
                organics = new_organics,
                goods = new_goods,
                energy = new_energy
            WHERE id = v_ship.id;
        END IF;
    END IF;

    -- Update port stock
    UPDATE public.ports SET 
        ore = v_port.ore,
        organics = v_port.organics,
        goods = v_port.goods,
        energy = v_port.energy
    WHERE id = p_port;

    -- Get final ship data
    SELECT credits, ore, organics, goods, energy INTO credits_after, new_ore, new_organics, new_goods, new_energy
    FROM public.ships WHERE id = v_ship.id;

    -- Return success
    RETURN jsonb_build_object(
        'ok', true,
        'port', jsonb_build_object(
            'kind', v_port.kind,
            'sector_number', v_port.sector_number
        ),
        'trades', jsonb_build_object(
            'sold', jsonb_build_object(
                'ore', sold_ore,
                'organics', sold_organics,
                'goods', sold_goods,
                'energy', sold_energy
            ),
            'bought', jsonb_build_object(
                pc, q
            )
        ),
        'credits', jsonb_build_object(
            'before', credits_after - proceeds + (q * sell_price),
            'after', credits_after
        ),
        'cargo', jsonb_build_object(
            'capacity', ship_cargo_capacity,
            'used', new_ore + new_organics + new_goods + new_energy,
            'free', ship_cargo_capacity - (new_ore + new_organics + new_goods + new_energy)
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Exception in restored game_trade_auto: %', SQLERRM;
        RETURN jsonb_build_object('error', jsonb_build_object('code','internal_error','message','Internal server error: ' || SQLERRM));
END;
$$;


ALTER FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_upgrade"("p_user_id" "uuid", "p_item" "text", "p_qty" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player_id UUID;
  v_ship_credits BIGINT;
  v_current_sector UUID;
  v_port_id UUID;
  v_ship_id UUID;
  v_fighters INTEGER;
  v_torpedoes INTEGER;
  v_unit_cost INTEGER;
  v_total_cost INTEGER;
  v_result JSON;
BEGIN
  -- Validate item type
  IF p_item NOT IN ('fighters', 'torpedoes') THEN
    RETURN json_build_object('error', 'Invalid item type');
  END IF;
  
  IF p_qty <= 0 THEN
    RETURN json_build_object('error', 'Quantity must be positive');
  END IF;
  
  -- Get player and ship data
  SELECT p.id, s.credits, p.current_sector, s.id
  INTO v_player_id, v_ship_credits, v_current_sector, v_ship_id
  FROM players p 
  JOIN ships s ON s.player_id = p.id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Player not found');
  END IF;

  -- Ensure there is a port in the player's current sector
  SELECT id INTO v_port_id FROM ports WHERE sector_id = v_current_sector;
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Must be at a port to upgrade');
  END IF;

  -- Get current ship stats
  SELECT fighters, torpedoes INTO v_fighters, v_torpedoes FROM ships WHERE id = v_ship_id;
  
  -- Set unit cost based on item type
  IF p_item = 'fighters' THEN
    v_unit_cost := 50;
  ELSIF p_item = 'torpedoes' THEN
    v_unit_cost := 120;
  END IF;
  
  v_total_cost := p_qty * v_unit_cost;
  
  -- Check if player has enough credits
  IF v_ship_credits < v_total_cost THEN
    RETURN json_build_object('error', 'Insufficient credits');
  END IF;
  
  -- Perform upgrade
  IF p_item = 'fighters' THEN
    UPDATE ships SET 
      fighters = fighters + p_qty,
      credits = credits - v_total_cost
    WHERE id = v_ship_id;
  ELSIF p_item = 'torpedoes' THEN
    UPDATE ships SET 
      torpedoes = torpedoes + p_qty,
      credits = credits - v_total_cost
    WHERE id = v_ship_id;
  END IF;
  
  -- Return success
  RETURN json_build_object(
    'success', true,
    'item', p_item,
    'quantity', p_qty,
    'cost', v_total_cost,
    'new_fighters', CASE WHEN p_item = 'fighters' THEN v_fighters + p_qty ELSE v_fighters END,
    'new_torpedoes', CASE WHEN p_item = 'torpedoes' THEN v_torpedoes + p_qty ELSE v_torpedoes END
  );
END;
$$;


ALTER FUNCTION "public"."game_upgrade"("p_user_id" "uuid", "p_item" "text", "p_qty" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_upgrade_ship"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_cost INTEGER;
    v_ship_credits BIGINT;
BEGIN
    -- Get player info
    IF p_universe_id IS NOT NULL THEN
        SELECT * INTO v_player FROM players WHERE user_id = p_user_id AND universe_id = p_universe_id;
    ELSE
        SELECT * INTO v_player FROM players WHERE user_id = p_user_id;
    END IF;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
    END IF;

    -- Get ship info
    SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'ship_not_found', 'message', 'Ship not found'));
    END IF;

    -- Calculate cost based on attribute and current level
    CASE p_attr
        WHEN 'engines' THEN v_cost := 500 * (v_ship.engine_lvl + 1);
        WHEN 'computer' THEN v_cost := 400 * (v_ship.comp_lvl + 1);
        WHEN 'sensors' THEN v_cost := 400 * (v_ship.sensor_lvl + 1);
        WHEN 'beams' THEN v_cost := 1500 * (v_ship.beam_weapon_lvl + 1);
        WHEN 'armor' THEN v_cost := 1000 * (v_ship.armor_max + 1);
        WHEN 'cloak' THEN v_cost := 750 * (v_ship.cloak_lvl + 1);
        WHEN 'torpedoes' THEN v_cost := 2000 * (v_ship.torp_launcher_lvl + 1);
        WHEN 'shields' THEN v_cost := 1500 * (v_ship.shield_lvl + 1);
        WHEN 'hull' THEN v_cost := 2000 * (v_ship.hull_lvl + 1);
    END CASE;

    -- Check if ship has enough credits
    IF v_ship.credits < v_cost THEN
        RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Insufficient credits for upgrade'));
    END IF;

    -- Apply upgrade and deduct credits
    CASE p_attr
        WHEN 'engines' THEN 
            UPDATE ships SET engine_lvl = engine_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'computer' THEN 
            UPDATE ships SET comp_lvl = comp_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'sensors' THEN 
            UPDATE ships SET sensor_lvl = sensor_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'beams' THEN 
            UPDATE ships SET beam_weapon_lvl = beam_weapon_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'armor' THEN 
            UPDATE ships SET armor_max = armor_max + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'cloak' THEN 
            UPDATE ships SET cloak_lvl = cloak_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'torpedoes' THEN 
            UPDATE ships SET torp_launcher_lvl = torp_launcher_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'shields' THEN 
            UPDATE ships SET shield_lvl = shield_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'hull' THEN 
            UPDATE ships SET hull_lvl = hull_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
    END CASE;

    -- Get updated ship data
    SELECT * INTO v_ship FROM ships WHERE id = v_ship.id;
    SELECT credits INTO v_ship_credits FROM ships WHERE id = v_ship.id;

    -- Return success with updated data
    RETURN jsonb_build_object(
        'ok', true,
        'credits', v_ship_credits,
        'ship', jsonb_build_object(
            'name', v_ship.name,
            'hull', v_ship.hull,
            'hull_max', v_ship.hull_max,
            'hull_lvl', v_ship.hull_lvl,
            'engine_lvl', v_ship.engine_lvl,
            'comp_lvl', v_ship.comp_lvl,
            'sensor_lvl', v_ship.sensor_lvl,
            'beam_weapon_lvl', v_ship.beam_weapon_lvl,
            'armor_max', v_ship.armor_max,
            'cloak_lvl', v_ship.cloak_lvl,
            'torp_launcher_lvl', v_ship.torp_launcher_lvl,
            'shield_lvl', v_ship.shield_lvl
        )
    );
END;
$$;


ALTER FUNCTION "public"."game_upgrade_ship"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."game_upgrade_ship_attr"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_cost INTEGER;
    v_ship_credits BIGINT;
BEGIN
    -- Get player info
    IF p_universe_id IS NOT NULL THEN
        SELECT * INTO v_player FROM players WHERE user_id = p_user_id AND universe_id = p_universe_id;
    ELSE
        SELECT * INTO v_player FROM players WHERE user_id = p_user_id;
    END IF;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
    END IF;

    -- Get ship info
    SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'ship_not_found', 'message', 'Ship not found'));
    END IF;

    -- Calculate cost based on attribute and current level
    CASE p_attr
        WHEN 'engines' THEN v_cost := 500 * (v_ship.engine_lvl + 1);
        WHEN 'computer' THEN v_cost := 400 * (v_ship.comp_lvl + 1);
        WHEN 'sensors' THEN v_cost := 400 * (v_ship.sensor_lvl + 1);
        WHEN 'beams' THEN v_cost := 1500 * (v_ship.beam_weapon_lvl + 1);
        WHEN 'armor' THEN v_cost := 1000 * (v_ship.armor_max + 1);
        WHEN 'cloak' THEN v_cost := 750 * (v_ship.cloak_lvl + 1);
        WHEN 'torpedoes' THEN v_cost := 2000 * (v_ship.torp_launcher_lvl + 1);
        WHEN 'shields' THEN v_cost := 1500 * (v_ship.shield_lvl + 1);
        WHEN 'hull' THEN v_cost := 2000 * (v_ship.hull_lvl + 1);
    END CASE;

    -- Check if ship has enough credits
    IF v_ship.credits < v_cost THEN
        RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
    END IF;

    -- Perform upgrade and deduct credits
    CASE p_attr
        WHEN 'engines' THEN 
            UPDATE ships SET engine_lvl = engine_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'computer' THEN 
            UPDATE ships SET comp_lvl = comp_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'sensors' THEN 
            UPDATE ships SET sensor_lvl = sensor_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'beams' THEN 
            UPDATE ships SET beam_weapon_lvl = beam_weapon_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'armor' THEN 
            UPDATE ships SET armor_max = armor_max + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'cloak' THEN 
            UPDATE ships SET cloak_lvl = cloak_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'torpedoes' THEN 
            UPDATE ships SET torp_launcher_lvl = torp_launcher_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'shields' THEN 
            UPDATE ships SET shield_lvl = shield_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
        WHEN 'hull' THEN 
            UPDATE ships SET hull_lvl = hull_lvl + 1, credits = credits - v_cost WHERE id = v_ship.id;
    END CASE;

    -- Get updated ship credits
    SELECT credits INTO v_ship_credits FROM ships WHERE id = v_ship.id;

    RETURN jsonb_build_object(
        'ok', true,
        'attribute', p_attr,
        'cost', v_cost,
        'credits_after', v_ship_credits
    );
END;
$$;


ALTER FUNCTION "public"."game_upgrade_ship_attr"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_ai_name"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    first_name TEXT;
    last_name TEXT;
    title TEXT;
    full_name TEXT;
BEGIN
    -- Get random first name
    SELECT name INTO first_name
    FROM public.ai_names
    WHERE name_type = 'first'
    ORDER BY RANDOM()
    LIMIT 1;
    
    -- Get random last name
    SELECT name INTO last_name
    FROM public.ai_names
    WHERE name_type = 'last'
    ORDER BY RANDOM()
    LIMIT 1;
    
    -- Get random title
    SELECT name INTO title
    FROM public.ai_names
    WHERE name_type = 'title'
    ORDER BY RANDOM()
    LIMIT 1;
    
    -- Combine into full name
    full_name := first_name || ' ' || last_name || ' ' || title;
    
    RETURN full_name;
END;
$$;


ALTER FUNCTION "public"."generate_ai_name"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_turns_for_universe"("p_universe_id" "uuid", "p_turns_to_add" integer) RETURNS TABLE("players_updated" integer, "total_turns_generated" integer, "players_at_cap" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_players_updated INTEGER := 0;
  v_total_turns_generated INTEGER := 0;
  v_players_at_cap INTEGER := 0;
  v_turn_cap INTEGER;
BEGIN
  -- Get the turn cap from universe settings
  SELECT max_accumulated_turns INTO v_turn_cap
  FROM public.universe_settings
  WHERE universe_id = p_universe_id;
  
  -- If no universe settings found, use default
  IF v_turn_cap IS NULL THEN
    v_turn_cap := 5000; -- Default from universe_settings schema
  END IF;
  
  -- Count players at cap first
  SELECT COUNT(*)::INTEGER INTO v_players_at_cap
  FROM public.players 
  WHERE universe_id = p_universe_id AND turns >= v_turn_cap;
  
  -- Update turns for all players in the universe who haven't reached their cap
  WITH updated_players AS (
    UPDATE public.players 
    SET 
      turns = LEAST(turns + p_turns_to_add, v_turn_cap),
      last_turn_ts = NOW()
    WHERE 
      universe_id = p_universe_id 
      AND turns < v_turn_cap
    RETURNING id, (LEAST(turns + p_turns_to_add, v_turn_cap) - turns) as turns_added
  )
  SELECT 
    COUNT(*)::INTEGER,
    COALESCE(SUM(turns_added), 0)::INTEGER
  INTO v_players_updated, v_total_turns_generated
  FROM updated_players;
  
  -- Return the results
  RETURN QUERY SELECT v_players_updated, v_total_turns_generated, v_players_at_cap;
END;
$$;


ALTER FUNCTION "public"."generate_turns_for_universe"("p_universe_id" "uuid", "p_turns_to_add" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_universe_news"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- TODO: Implement news generation logic
    -- This should generate random news events for the universe
    
    RETURN jsonb_build_object(
        'message', 'News generation placeholder - not yet implemented',
        'universe_id', p_universe_id,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."generate_universe_news"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ai_activity_summary"("p_universe_id" "uuid", "p_hours" integer DEFAULT 24) RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  WITH recent AS (
    SELECT *
    FROM public.ai_action_log
    WHERE universe_id = p_universe_id
      AND created_at >= now() - make_interval(hours => GREATEST(1, p_hours))
  )
  SELECT jsonb_build_object(
    'since_hours', GREATEST(1, p_hours),
    'total_actions', COUNT(*),
    'players_involved', COUNT(DISTINCT player_id),
    'trades', COUNT(*) FILTER (WHERE action = 'trade'),
    'upgrades', COUNT(*) FILTER (WHERE action = 'upgrade'),
    'claims', COUNT(*) FILTER (WHERE action = 'claim_planet'),
    'moves', COUNT(*) FILTER (WHERE action = 'move' OR action = 'hyperspace'),
    'last_action_at', MAX(created_at)
  )
  FROM recent;
$$;


ALTER FUNCTION "public"."get_ai_activity_summary"("p_universe_id" "uuid", "p_hours" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ai_dashboard_stats"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_stats jsonb;
  v_total_ai int;
  v_active_ai int;
  v_actions_last_hour int;
  v_avg_credits numeric;
  v_total_planets int;
  v_personality_dist jsonb;
BEGIN
  -- Get total AI players
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players
  WHERE universe_id = p_universe_id AND is_ai = true;

  -- Get active AI (with turns > 0)
  SELECT COUNT(*) INTO v_active_ai
  FROM public.players
  WHERE universe_id = p_universe_id AND is_ai = true AND turns > 0;

  -- Get actions in last hour
  SELECT COUNT(*) INTO v_actions_last_hour
  FROM public.ai_action_log
  WHERE universe_id = p_universe_id 
    AND created_at > NOW() - INTERVAL '1 hour'
    AND outcome = 'success';

  -- Get average credits
  SELECT COALESCE(AVG(s.credits), 0) INTO v_avg_credits
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;

  -- Get total AI-owned planets
  SELECT COUNT(*) INTO v_total_planets
  FROM public.planets pl
  JOIN public.players p ON p.id = pl.owner_player_id
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;

  -- Get personality distribution
  SELECT jsonb_object_agg(
    COALESCE(ai_personality::text, 'unknown'), 
    count
  ) INTO v_personality_dist
  FROM (
    SELECT ai_personality, COUNT(*) as count
    FROM public.players
    WHERE universe_id = p_universe_id AND is_ai = true
    GROUP BY ai_personality
  ) sub;

  -- Build result
  v_stats := jsonb_build_object(
    'total_ai_players', v_total_ai,
    'active_ai_players', v_active_ai,
    'actions_last_hour', v_actions_last_hour,
    'average_credits', ROUND(v_avg_credits),
    'total_ai_planets', v_total_planets,
    'personality_distribution', COALESCE(v_personality_dist, '{}'::jsonb)
  );

  RETURN v_stats;
END;
$$;


ALTER FUNCTION "public"."get_ai_dashboard_stats"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ai_debug_snapshot"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  WITH ai AS (
    SELECT id, handle, current_sector, turns, turns_spent
    FROM public.players
    WHERE universe_id = p_universe_id AND is_ai = TRUE
  ),
  mem AS (
    SELECT m.player_id, m.current_goal, m.target_sector_id
    FROM public.ai_player_memory m
    JOIN ai ON ai.id = m.player_id
  ),
  rec AS (
    SELECT COUNT(*) AS recent_actions,
           COUNT(DISTINCT player_id) AS recent_ai
    FROM public.ai_action_log
    WHERE universe_id = p_universe_id
      AND created_at >= now() - interval '1 hour'
  ),
  ports AS (
    SELECT COUNT(*) AS ports_count FROM public.ports p
    JOIN public.sectors s ON s.id = p.sector_id AND s.universe_id = p_universe_id
  ),
  sample AS (
    SELECT a.id, a.turns, a.turns_spent, a.current_sector,
           (SELECT jsonb_build_object('goal', m.current_goal, 'target_sector_id', m.target_sector_id, 'target_planet_id', NULL)
            FROM mem m WHERE m.player_id = a.id) AS memory
    FROM ai a
    ORDER BY a.id
    LIMIT 5
  )
  SELECT jsonb_build_object(
    'ai_players', (SELECT jsonb_build_object('count', COUNT(*)) FROM ai),
    'ports', (SELECT jsonb_build_object('count', ports_count) FROM ports),
    'recent', (SELECT jsonb_build_object('actions_last_hour', recent_actions, 'ai_last_hour', recent_ai) FROM rec),
    'sample_ai', (SELECT jsonb_agg(jsonb_build_object(
                    'player_id', id,
                    'turns', turns,
                    'turns_spent', turns_spent,
                    'current_sector', current_sector,
                    'memory', memory
                  )) FROM sample)
  );
$$;


ALTER FUNCTION "public"."get_ai_debug_snapshot"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ai_performance_metrics"("p_universe_id" "uuid") RETURNS TABLE("player_id" "uuid", "player_name" "text", "ai_personality" "text", "credits" bigint, "owned_planets" integer, "total_actions" integer, "last_action" timestamp without time zone, "current_goal" "text", "last_profit" bigint, "consecutive_losses" integer, "performance_score" double precision)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id as player_id,
        p.name as player_name,
        p.ai_personality::TEXT,
        s.credits,
        COALESCE(m.owned_planets, 0) as owned_planets,
        COALESCE((
            SELECT COUNT(*) 
            FROM ai_player_memory mem 
            WHERE mem.player_id = p.id 
            AND mem.updated_at >= CURRENT_DATE - INTERVAL '7 days'
        ), 0)::INTEGER as total_actions,
        m.last_action,
        m.current_goal,
        COALESCE(m.last_profit, 0) as last_profit,
        COALESCE(m.consecutive_losses, 0) as consecutive_losses,
        -- Calculate performance score based on credits, planets, and recent activity
        (
            (s.credits / 10000.0) + 
            (COALESCE(m.owned_planets, 0) * 5.0) +
            (CASE WHEN m.last_action >= CURRENT_DATE - INTERVAL '1 day' THEN 10.0 ELSE 0.0 END) -
            (COALESCE(m.consecutive_losses, 0) * 2.0)
        ) as performance_score
    FROM players p
    JOIN ships s ON p.id = s.player_id
    LEFT JOIN ai_player_memory m ON p.id = m.player_id
    WHERE p.universe_id = p_universe_id 
    AND p.is_ai = TRUE
    ORDER BY performance_score DESC;
END;
$$;


ALTER FUNCTION "public"."get_ai_performance_metrics"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ai_players"("p_universe_id" "uuid") RETURNS TABLE("player_id" "uuid", "player_name" "text", "ship_id" "uuid", "sector_number" integer, "credits" bigint, "ai_personality" "text", "score" bigint, "turns" integer, "owned_planets" bigint, "ship_levels" "jsonb", "last_action" "text", "current_goal" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id as player_id,
    p.handle as player_name,
    s.id as ship_id,
    sec.number as sector_number,
    s.credits,
    p.ai_personality::text,
    -- Read score from players table
    COALESCE(p.score, 0) as score,
    COALESCE(p.turns, 0) as turns,
    -- Count actual planets owned by this AI player
    COALESCE(planet_counts.planet_count, 0) as owned_planets,
    -- Ship levels as JSON
    jsonb_build_object(
      'hull', s.hull_lvl,
      'engine', s.engine_lvl,
      'power', COALESCE(s.power_lvl, 0),
      'computer', s.comp_lvl,
      'sensors', s.sensor_lvl,
      'beam_weapon', COALESCE(s.beam_lvl, 0),
      'armor', 0,
      'cloak', COALESCE(s.cloak_lvl, 0),
      'torp_launcher', COALESCE(s.torp_launcher_lvl, 0),
      'shield', s.shield_lvl
    ) as ship_levels,
    -- Get last action from ai_action_log
    (SELECT aal.action FROM ai_action_log aal
     WHERE aal.player_id = p.id 
     ORDER BY aal.created_at DESC 
     LIMIT 1) as last_action,
    -- Get current goal from ai_player_memory
    COALESCE(m.current_goal, 'explore') as current_goal
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  JOIN public.sectors sec ON sec.id = p.current_sector
  LEFT JOIN public.ai_player_memory m ON m.player_id = p.id
  LEFT JOIN (
    -- Count planets owned by each AI player
    SELECT 
      pl.owner_player_id,
      COUNT(*) as planet_count
    FROM public.planets pl
    JOIN public.players p2 ON p2.id = pl.owner_player_id
    WHERE p2.universe_id = p_universe_id 
      AND p2.is_ai = true
    GROUP BY pl.owner_player_id
  ) planet_counts ON planet_counts.owner_player_id = p.id
  WHERE p.universe_id = p_universe_id 
    AND p.is_ai = true
  ORDER BY p.score DESC NULLS LAST, p.handle;
END;
$$;


ALTER FUNCTION "public"."get_ai_players"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ai_statistics"("p_universe_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_total_ai_players INTEGER;
    v_active_ai_players INTEGER;
    v_total_actions_today INTEGER;
    v_average_credits BIGINT;
    v_total_ai_planets INTEGER;
    v_personality_distribution JSON;
    v_result JSON;
BEGIN
    -- Count total AI players
    SELECT COUNT(*) INTO v_total_ai_players
    FROM players p
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;
    
    -- Count active AI players (those with recent activity)
    SELECT COUNT(*) INTO v_active_ai_players
    FROM players p
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = TRUE 
      AND p.last_turn_ts > NOW() - INTERVAL '24 hours';
    
    -- Count total actions today (sum of turns_spent for AI players)
    SELECT COALESCE(SUM(p.turns_spent), 0) INTO v_total_actions_today
    FROM players p
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = TRUE 
      AND p.last_turn_ts > NOW() - INTERVAL '24 hours';
    
    -- Calculate average credits for AI players
    SELECT COALESCE(AVG(s.credits), 0) INTO v_average_credits
    FROM players p
    JOIN ships s ON p.id = s.player_id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;
    
    -- Count AI owned planets
    SELECT COUNT(*) INTO v_total_ai_planets
    FROM planets pl
    JOIN players p ON pl.owner_player_id = p.id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;
    
    -- Get personality distribution
    SELECT json_object_agg(
        ai_personality, 
        personality_count
    ) INTO v_personality_distribution
    FROM (
        SELECT 
            COALESCE(p.ai_personality, 'balanced') as ai_personality,
            COUNT(*) as personality_count
        FROM players p
        WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
        GROUP BY COALESCE(p.ai_personality, 'balanced')
    ) personality_stats;
    
    -- Build result
    v_result := json_build_object(
        'total_ai_players', v_total_ai_players,
        'active_ai_players', v_active_ai_players,
        'total_actions_today', v_total_actions_today,
        'average_credits', v_average_credits,
        'total_ai_planets', v_total_ai_planets,
        'personality_distribution', COALESCE(v_personality_distribution, '{}'::json)
    );
    
    RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."get_ai_statistics"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cron_log_summary"("p_universe_id" "uuid") RETURNS TABLE("event_type" "text", "event_name" "text", "last_execution" timestamp with time zone, "last_status" "text", "last_message" "text", "execution_count_24h" integer, "avg_execution_time_ms" numeric)
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cl.event_type,
        cl.event_name,
        MAX(cl.triggered_at) as last_execution,
        (SELECT cl2.status FROM public.cron_logs cl2 
         WHERE cl2.universe_id = p_universe_id AND cl2.event_type = cl.event_type 
         ORDER BY cl2.triggered_at DESC LIMIT 1) as last_status,
        (SELECT cl2.message FROM public.cron_logs cl2 
         WHERE cl2.universe_id = p_universe_id AND cl2.event_type = cl.event_type 
         ORDER BY cl2.triggered_at DESC LIMIT 1) as last_message,
        COUNT(*) FILTER (WHERE cl.triggered_at >= now() - interval '24 hours') as execution_count_24h,
        AVG(cl.execution_time_ms) FILTER (WHERE cl.execution_time_ms IS NOT NULL) as avg_execution_time_ms
    FROM public.cron_logs cl
    WHERE cl.universe_id = p_universe_id
    GROUP BY cl.event_type, cl.event_name
    ORDER BY MAX(cl.triggered_at) DESC;
END;
$$;


ALTER FUNCTION "public"."get_cron_log_summary"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cron_logs"("p_universe_id" "uuid", "p_limit" integer DEFAULT 50) RETURNS TABLE("id" "uuid", "event_type" "text", "event_name" "text", "status" "text", "message" "text", "execution_time_ms" integer, "triggered_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cl.id,
        cl.event_type,
        cl.event_name,
        cl.status,
        cl.message,
        cl.execution_time_ms,
        cl.triggered_at,
        cl.metadata
    FROM public.cron_logs cl
    WHERE cl.universe_id = p_universe_id
    ORDER BY cl.triggered_at DESC
    LIMIT p_limit;
END;
$$;


ALTER FUNCTION "public"."get_cron_logs"("p_universe_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_emergency_warp_status"("p_player_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_ship RECORD;
    v_avg_tech numeric;
    v_degradation_threshold numeric;
    v_universe_id uuid;
BEGIN
    -- Get ship data
    SELECT * INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    -- Get universe_id
    SELECT universe_id INTO v_universe_id
    FROM public.players
    WHERE id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Ship not found');
    END IF;
    
    -- Calculate average tech level
    v_avg_tech := public.calculate_ship_avg_tech_level(p_player_id);
    
    -- Get degradation threshold from universe settings
    SELECT avg_tech_level_emergency_warp_degrades INTO v_degradation_threshold
    FROM public.universe_settings
    WHERE universe_id = v_universe_id;
    
    -- Default threshold if not set
    IF v_degradation_threshold IS NULL THEN
        v_degradation_threshold := 13;
    END IF;
    
    RETURN jsonb_build_object(
        'device_installed', v_ship.device_emergency_warp,
        'avg_tech_level', v_avg_tech,
        'degradation_threshold', v_degradation_threshold,
        'will_degrade', v_avg_tech >= v_degradation_threshold,
        'estimated_damage', CASE 
            WHEN v_avg_tech >= v_degradation_threshold THEN 
                GREATEST(1, FLOOR((v_avg_tech - v_degradation_threshold) * 2))
            ELSE 0
        END
    );
END;
$$;


ALTER FUNCTION "public"."get_emergency_warp_status"("p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_first_available_universe"() RETURNS TABLE("universe_id" "uuid", "universe_name" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT u.id, u.name
  FROM universes u
  ORDER BY u.created_at ASC
  LIMIT 1;
END;
$$;


ALTER FUNCTION "public"."get_first_available_universe"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_leaderboard"("p_universe_id" "uuid", "p_limit" integer DEFAULT 50, "p_ai_only" boolean DEFAULT false) RETURNS TABLE("rank" integer, "player_id" "uuid", "player_name" "text", "handle" "text", "score" bigint, "turns_spent" bigint, "last_login" timestamp with time zone, "is_online" boolean, "is_ai" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ROW_NUMBER() OVER (ORDER BY p.score DESC)::INTEGER as rank,
    p.id as player_id,
    p.handle as player_name,
    p.handle,
    COALESCE(p.score, 0) as score,
    COALESCE(p.turns_spent, 0) as turns_spent,
    p.last_login,
    (p.last_login IS NOT NULL AND p.last_login > NOW() - INTERVAL '30 minutes') as is_online,
    COALESCE(p.is_ai, FALSE) as is_ai
  FROM players p
  WHERE 
    p.universe_id = p_universe_id
    AND (p_ai_only = FALSE OR p.is_ai = TRUE)
    AND (p_ai_only = TRUE OR p.is_ai = FALSE OR p.is_ai IS NULL)
  ORDER BY p.score DESC
  LIMIT p_limit;
END;
$$;


ALTER FUNCTION "public"."get_leaderboard"("p_universe_id" "uuid", "p_limit" integer, "p_ai_only" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_leaderboard_stats"("p_universe_id" "uuid") RETURNS TABLE("total_players" integer, "total_ai_players" integer, "total_human_players" integer, "players_online" integer, "total_credits" bigint, "total_planets" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*)::INTEGER as total_players,
        COUNT(*) FILTER (WHERE p.is_ai = TRUE)::INTEGER as total_ai_players,
        COUNT(*) FILTER (WHERE p.is_ai = FALSE OR p.is_ai IS NULL)::INTEGER as total_human_players,
        COUNT(*) FILTER (WHERE p.last_login IS NOT NULL AND p.last_login > NOW() - INTERVAL '30 minutes')::INTEGER as players_online,
        COALESCE(SUM(s.credits), 0)::BIGINT as total_credits,
        (SELECT COUNT(*)::INTEGER FROM planets pl WHERE pl.owner_player_id IS NOT NULL) as total_planets
    FROM players p
    LEFT JOIN ships s ON s.player_id = p.id
    WHERE p.universe_id = p_universe_id;
END;
$$;


ALTER FUNCTION "public"."get_leaderboard_stats"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_next_scheduled_events"("p_universe_id" "uuid") RETURNS TABLE("next_turn_generation" timestamp with time zone, "next_cycle_event" timestamp with time zone, "next_update_event" timestamp with time zone, "turns_until_next_turn_generation" integer, "minutes_until_next_cycle" integer, "minutes_until_next_update" integer)
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_settings RECORD;
    v_now timestamp with time zone := now();
BEGIN
    -- Get universe settings
    SELECT * INTO v_settings FROM public.universe_settings WHERE universe_id = p_universe_id;
    
    -- If no settings found, return nulls
    IF NOT FOUND THEN
        RETURN QUERY SELECT NULL::timestamp with time zone, NULL::timestamp with time zone, NULL::timestamp with time zone, NULL::integer, NULL::integer, NULL::integer;
        RETURN;
    END IF;
    
    -- Calculate next events
    RETURN QUERY
    SELECT 
        -- Next turn generation
        CASE 
            WHEN v_settings.last_turn_generation IS NULL THEN v_now
            ELSE v_settings.last_turn_generation + (v_settings.turn_generation_interval_minutes || ' minutes')::interval
        END::timestamp with time zone,
        
        -- Next cycle event
        CASE 
            WHEN v_settings.last_cycle_event IS NULL THEN v_now
            ELSE v_settings.last_cycle_event + (v_settings.cycle_interval_minutes || ' minutes')::interval
        END::timestamp with time zone,
        
        -- Next update event
        CASE 
            WHEN v_settings.last_update_event IS NULL THEN v_now
            ELSE v_settings.last_update_event + (v_settings.update_interval_minutes || ' minutes')::interval
        END::timestamp with time zone,
        
        -- Turns until next turn generation (always 0 since turns are generated immediately)
        0::integer,
        
        -- Minutes until next cycle event
        CASE 
            WHEN v_settings.last_cycle_event IS NULL THEN 0
            ELSE EXTRACT(EPOCH FROM (v_settings.last_cycle_event + (v_settings.cycle_interval_minutes || ' minutes')::interval - v_now)) / 60
        END::integer,
        
        -- Minutes until next update event
        CASE 
            WHEN v_settings.last_update_event IS NULL THEN 0
            ELSE EXTRACT(EPOCH FROM (v_settings.last_update_event + (v_settings.update_interval_minutes || ' minutes')::interval - v_now)) / 60
        END::integer;
END;
$$;


ALTER FUNCTION "public"."get_next_scheduled_events"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_planet_owner_player_id"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_player_id UUID;
BEGIN
  -- Get the player ID that owns the planet for this user
  SELECT pl.id INTO v_player_id
  FROM planets p
  JOIN players pl ON p.owner_player_id = pl.id
  WHERE p.id = p_planet_id 
  AND pl.user_id = p_user_id 
  AND pl.universe_id = p_universe_id
  LIMIT 1;
  
  RETURN v_player_id;
END;
$$;


ALTER FUNCTION "public"."get_planet_owner_player_id"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_player_for_user_in_universe"("p_user_id" "uuid", "p_universe_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_player_id UUID;
BEGIN
  -- Get the player ID for this user in this universe
  -- If there are multiple players (due to the bug), get the first one
  SELECT id INTO v_player_id
  FROM players 
  WHERE user_id = p_user_id 
  AND universe_id = p_universe_id
  ORDER BY created_at ASC  -- Get the oldest player (first created)
  LIMIT 1;
  
  RETURN v_player_id;
END;
$$;


ALTER FUNCTION "public"."get_player_for_user_in_universe"("p_user_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_player_inventory"("p_player_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  v_ship ships;
  v_inventory JSONB;
BEGIN
  SELECT * INTO v_ship FROM ships WHERE player_id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Ship not found');
  END IF;
  
  v_inventory := jsonb_build_object(
    'ore', v_ship.ore,
    'organics', v_ship.organics,
    'goods', v_ship.goods,
    'energy', v_ship.energy,
    'colonists', v_ship.colonists
  );
  
  RETURN v_inventory;
END;
$$;


ALTER FUNCTION "public"."get_player_inventory"("p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_player_trade_routes"("p_user_id" "uuid", "p_universe_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_routes JSONB := '[]'::jsonb;
    v_route RECORD;
    v_waypoints JSONB;
BEGIN
    -- Get player ID
    SELECT id INTO v_player_id
    FROM players 
    WHERE user_id = p_user_id AND universe_id = p_universe_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found in this universe'));
    END IF;
    
    -- Get all routes for this player
    FOR v_route IN 
        SELECT tr.*, 
               COUNT(rw.id) as waypoint_count,
               MAX(rp.profit_per_turn) as current_profit_per_turn
        FROM trade_routes tr
        LEFT JOIN route_waypoints rw ON tr.id = rw.route_id
        LEFT JOIN route_profitability rp ON tr.id = rp.route_id AND rp.is_current = true
        WHERE tr.player_id = v_player_id
        GROUP BY tr.id
        ORDER BY tr.created_at DESC
    LOOP
        -- Get waypoints for this route
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', rw.id,
                'sequence_order', rw.sequence_order,
                'port_id', rw.port_id,
                'action_type', rw.action_type,
                'resource', rw.resource,
                'quantity', rw.quantity,
                'notes', rw.notes,
                'port_info', jsonb_build_object(
                    'sector_number', s.number,
                    'port_kind', p.kind
                )
            ) ORDER BY rw.sequence_order
        )
        INTO v_waypoints
        FROM route_waypoints rw
        JOIN ports p ON rw.port_id = p.id
        JOIN sectors s ON p.sector_id = s.id
        WHERE rw.route_id = v_route.id;
        
        v_routes := v_routes || jsonb_build_object(
            'id', v_route.id,
            'name', v_route.name,
            'description', v_route.description,
            'is_active', v_route.is_active,
            'is_automated', v_route.is_automated,
            'max_iterations', v_route.max_iterations,
            'current_iteration', v_route.current_iteration,
            'total_profit', v_route.total_profit,
            'total_turns_spent', v_route.total_turns_spent,
            'waypoint_count', v_route.waypoint_count,
            'current_profit_per_turn', v_route.current_profit_per_turn,
            'created_at', v_route.created_at,
            'updated_at', v_route.updated_at,
            'last_executed_at', v_route.last_executed_at,
            'waypoints', COALESCE(v_waypoints, '[]'::jsonb)
        );
    END LOOP;
    
    RETURN json_build_object('ok', true, 'routes', v_routes);
END;
$$;


ALTER FUNCTION "public"."get_player_trade_routes"("p_user_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_sector_degrees_by_name"("p_universe_name" "text") RETURNS TABLE("number" integer, "degree" integer)
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  WITH u AS (SELECT id FROM universes WHERE name = p_universe_name)
  SELECT s.number,
         COALESCE(
           (
             SELECT COUNT(*) FROM (
               SELECT DISTINCT CASE WHEN w.from_sector = s.id THEN w.to_sector ELSE w.from_sector END AS nbr
               FROM warps w
               WHERE w.universe_id = s.universe_id
                 AND (w.from_sector = s.id OR w.to_sector = s.id)
             ) q
           ), 0
         ) AS degree
  FROM sectors s
  WHERE s.universe_id = (SELECT id FROM u)
  ORDER BY s.number;
$$;


ALTER FUNCTION "public"."get_sector_degrees_by_name"("p_universe_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_sector_mine_info"("p_sector_id" "uuid", "p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_mine_count integer;
    v_total_torpedoes integer;
    v_deployed_by_players jsonb;
BEGIN
    -- Count active mines and total torpedoes
    SELECT COUNT(*), SUM(torpedoes_used)
    INTO v_mine_count, v_total_torpedoes
    FROM public.mines
    WHERE sector_id = p_sector_id 
      AND universe_id = p_universe_id 
      AND is_active = true;
    
    -- Get info about who deployed mines
    SELECT jsonb_agg(
        jsonb_build_object(
            'player_handle', p.handle,
            'torpedoes_used', m.torpedoes_used,
            'deployed_at', m.created_at
        )
    )
    INTO v_deployed_by_players
    FROM public.mines m
    JOIN public.players p ON p.id = m.deployed_by
    WHERE m.sector_id = p_sector_id 
      AND m.universe_id = p_universe_id 
      AND m.is_active = true;
    
    RETURN jsonb_build_object(
        'mine_count', v_mine_count,
        'total_torpedoes', COALESCE(v_total_torpedoes, 0),
        'deployed_by', COALESCE(v_deployed_by_players, '[]'::jsonb),
        'has_mines', v_mine_count > 0
    );
END;
$$;


ALTER FUNCTION "public"."get_sector_mine_info"("p_sector_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ship_capacity"("p_ship_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    ship_record RECORD;
    result JSONB;
BEGIN
    -- Get ship data including generated max columns
    SELECT 
        hull_lvl,
        hull_max,
        comp_lvl,
        armor_lvl,
        armor_max,
        power_lvl,
        energy_max,
        torp_launcher_lvl
    INTO ship_record
    FROM public.ships
    WHERE id = p_ship_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Ship not found');
    END IF;
    
    -- Use generated max columns directly (no need to calculate)
    result := jsonb_build_object(
        'hull', jsonb_build_object(
            'level', COALESCE(ship_record.hull_lvl, 1),
            'capacity', COALESCE(ship_record.hull_max, 100),
            'description', 'Cargo capacity (ore, organics, goods, energy, colonists)'
        ),
        'computer', jsonb_build_object(
            'level', COALESCE(ship_record.comp_lvl, 1),
            'capacity', public.calculate_bnt_capacity(COALESCE(ship_record.comp_lvl, 1) - 1),
            'description', 'Fighter capacity'
        ),
        'armor', jsonb_build_object(
            'level', COALESCE(ship_record.armor_lvl, 1),
            'capacity', COALESCE(ship_record.armor_max, 0),
            'description', 'Armor points capacity'
        ),
        'power', jsonb_build_object(
            'level', COALESCE(ship_record.power_lvl, 1),
            'capacity', COALESCE(ship_record.energy_max, 100),
            'description', 'Energy capacity'
        ),
        'torp_launcher', jsonb_build_object(
            'level', COALESCE(ship_record.torp_launcher_lvl, 1),
            'capacity', public.calculate_bnt_capacity(COALESCE(ship_record.torp_launcher_lvl, 1) - 1),
            'description', 'Torpedo capacity'
        )
    );
    
    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_ship_capacity"("p_ship_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_ship_capacity"("p_ship_id" "uuid") IS 'Returns comprehensive ship capacity breakdown using BNT formula for all tech levels';



CREATE OR REPLACE FUNCTION "public"."get_ship_capacity_data"("p_ship_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_ship ships;
  v_capacity_data JSONB;
BEGIN
  SELECT * INTO v_ship FROM ships WHERE id = p_ship_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ship not found for ID %', p_ship_id;
  END IF;

  -- Calculate capacity data directly (no need for separate function)
  v_capacity_data := jsonb_build_object(
    'fighters', jsonb_build_object(
      'max', v_ship.comp_lvl * 10,
      'current', v_ship.fighters,
      'level', v_ship.comp_lvl
    ),
    'torpedoes', jsonb_build_object(
      'max', v_ship.torp_launcher_lvl * 10,
      'current', v_ship.torpedoes,
      'level', v_ship.torp_launcher_lvl
    ),
    'armor', jsonb_build_object(
      'max', v_ship.armor_max,
      'current', v_ship.armor,
      'level', v_ship.armor_max -- Using armor_max as level
    ),
    'colonists', jsonb_build_object(
      'max', v_ship.cargo,
      'current', v_ship.colonists,
      'level', v_ship.hull_lvl
    ),
    'energy', jsonb_build_object(
      'max', v_ship.power_lvl * 100,
      'current', v_ship.energy,
      'level', v_ship.power_lvl
    ),
    'devices', jsonb_build_object(
      'space_beacons', jsonb_build_object(
        'max', 10,
        'current', v_ship.device_space_beacons,
        'cost', 1000000
      ),
      'warp_editors', jsonb_build_object(
        'max', 5,
        'current', v_ship.device_warp_editors,
        'cost', 1000000
      ),
      'genesis_torpedoes', jsonb_build_object(
        'max', 3,
        'current', v_ship.device_genesis_torpedoes,
        'cost', 5000000
      ),
      'mine_deflectors', jsonb_build_object(
        'max', 1,
        'current', v_ship.device_mine_deflectors,
        'cost', 2000000
      ),
      'emergency_warp', jsonb_build_object(
        'max', 1,
        'current', v_ship.device_emergency_warp,
        'cost', 1000000
      ),
      'escape_pod', jsonb_build_object(
        'max', 1,
        'current', v_ship.device_escape_pod,
        'cost', 500000
      ),
      'fuel_scoop', jsonb_build_object(
        'max', 1,
        'current', v_ship.device_fuel_scoop,
        'cost', 250000
      ),
      'last_seen', jsonb_build_object(
        'max', 1,
        'current', v_ship.device_last_seen,
        'cost', 10000000
      )
    )
  );

  RETURN v_capacity_data;
END;
$$;


ALTER FUNCTION "public"."get_ship_capacity_data"("p_ship_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_ship_capacity_data"("p_ship_id" "uuid") IS 'Updated to work with merged ships table';



CREATE OR REPLACE FUNCTION "public"."get_universe_settings"("p_universe_id" "uuid") RETURNS TABLE("universe_id" "uuid", "game_version" "text", "game_name" "text", "avg_tech_level_mines" integer, "avg_tech_emergency_warp_degrade" integer, "max_avg_tech_federation_sectors" integer, "tech_level_upgrade_bases" integer, "number_of_sectors" integer, "max_links_per_sector" integer, "max_planets_per_sector" integer, "planets_needed_for_sector_ownership" integer, "igb_enabled" boolean, "igb_interest_rate_per_update" numeric, "igb_loan_rate_per_update" numeric, "planet_interest_rate" numeric, "colonists_limit" bigint, "colonist_production_rate" numeric, "colonists_per_fighter" integer, "colonists_per_torpedo" integer, "colonists_per_ore" integer, "colonists_per_organics" integer, "colonists_per_goods" integer, "colonists_per_energy" integer, "colonists_per_credits" integer, "max_accumulated_turns" integer, "max_traderoutes_per_player" integer, "energy_per_sector_fighter" numeric, "sector_fighter_degradation_rate" numeric, "tick_interval_minutes" integer, "turns_generation_interval_minutes" integer, "turns_per_generation" integer, "defenses_check_interval_minutes" integer, "xenobes_play_interval_minutes" integer, "igb_interest_accumulation_interval_minutes" integer, "news_generation_interval_minutes" integer, "planet_production_interval_minutes" integer, "port_regeneration_interval_minutes" integer, "ships_tow_from_fed_sectors_interval_minutes" integer, "rankings_generation_interval_minutes" integer, "sector_defenses_degrade_interval_minutes" integer, "planetary_apocalypse_interval_minutes" integer, "use_new_planet_update_code" boolean, "limit_captured_planets_max_credits" boolean, "captured_planets_max_credits" bigint, "turn_generation_interval_minutes" integer, "cycle_interval_minutes" integer, "update_interval_minutes" integer, "last_turn_generation" timestamp with time zone, "last_cycle_event" timestamp with time zone, "last_update_event" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    us.universe_id,
    us.game_version,
    us.game_name,
    us.avg_tech_level_mines,
    us.avg_tech_emergency_warp_degrade,
    us.max_avg_tech_federation_sectors,
    us.tech_level_upgrade_bases,
    us.number_of_sectors,
    us.max_links_per_sector,
    us.max_planets_per_sector,
    us.planets_needed_for_sector_ownership,
    us.igb_enabled,
    us.igb_interest_rate_per_update,
    us.igb_loan_rate_per_update,
    us.planet_interest_rate,
    us.colonists_limit,
    us.colonist_production_rate,
    us.colonists_per_fighter,
    us.colonists_per_torpedo,
    us.colonists_per_ore,
    us.colonists_per_organics,
    us.colonists_per_goods,
    us.colonists_per_energy,
    us.colonists_per_credits,
    us.max_accumulated_turns,
    us.max_traderoutes_per_player,
    us.energy_per_sector_fighter,
    us.sector_fighter_degradation_rate,
    us.tick_interval_minutes,
    us.turns_generation_interval_minutes,
    us.turns_per_generation,
    us.defenses_check_interval_minutes,
    us.xenobes_play_interval_minutes,
    us.igb_interest_accumulation_interval_minutes,
    us.news_generation_interval_minutes,
    us.planet_production_interval_minutes,
    us.port_regeneration_interval_minutes,
    us.ships_tow_from_fed_sectors_interval_minutes,
    us.rankings_generation_interval_minutes,
    us.sector_defenses_degrade_interval_minutes,
    us.planetary_apocalypse_interval_minutes,
    us.use_new_planet_update_code,
    us.limit_captured_planets_max_credits,
    us.captured_planets_max_credits,
    us.turn_generation_interval_minutes,
    us.cycle_interval_minutes,
    us.update_interval_minutes,
    us.last_turn_generation,
    us.last_cycle_event,
    us.last_update_event
  FROM universe_settings us
  WHERE us.universe_id = p_universe_id;
END;
$$;


ALTER FUNCTION "public"."get_universe_settings"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_user_admin"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE((SELECT up.is_admin FROM public.user_profiles up WHERE up.user_id = p_user_id), false);
$$;


ALTER FUNCTION "public"."is_user_admin"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_universes"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_result jsonb := '[]'::jsonb;
  v_universe record;
  v_sector_count INTEGER;
  v_port_count INTEGER;
  v_planet_count INTEGER;
  v_player_count INTEGER;
BEGIN
  FOR v_universe IN 
    SELECT id, name, created_at 
    FROM universes 
    ORDER BY created_at DESC
  LOOP
    -- Count sectors
    SELECT COUNT(*) INTO v_sector_count FROM sectors WHERE universe_id = v_universe.id;
    
    -- Count ports
    SELECT COUNT(*) INTO v_port_count 
    FROM ports p 
    JOIN sectors s ON p.sector_id = s.id 
    WHERE s.universe_id = v_universe.id;
    
    -- Count planets
    SELECT COUNT(*) INTO v_planet_count 
    FROM planets pl 
    JOIN sectors s ON pl.sector_id = s.id 
    WHERE s.universe_id = v_universe.id;
    
    -- Count players
    SELECT COUNT(*) INTO v_player_count FROM players WHERE universe_id = v_universe.id;
    
    v_result := v_result || jsonb_build_object(
      'id', v_universe.id,
      'name', v_universe.name,
      'created_at', v_universe.created_at,
      'sector_count', v_sector_count,
      'port_count', v_port_count,
      'planet_count', v_planet_count,
      'player_count', v_player_count
    );
  END LOOP;
  
  RETURN jsonb_build_object('ok', true, 'universes', v_result);
END;
$$;


ALTER FUNCTION "public"."list_universes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action_type" "text", "p_outcome" "text", "p_details" "jsonb" DEFAULT NULL::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO public.ai_action_log (
    player_id,
    universe_id,
    action_type,
    outcome,
    details,
    timestamp
  ) VALUES (
    p_player_id,
    p_universe_id,
    p_action_type,
    p_outcome,
    p_details,
    NOW()
  );
EXCEPTION WHEN OTHERS THEN
  -- Silently ignore logging errors to prevent AI from failing
  NULL;
END;
$$;


ALTER FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action_type" "text", "p_outcome" "text", "p_details" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text", "p_outcome" "text", "p_message" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text", "p_outcome" "text", "p_message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_ai_action"("p_universe_id" "uuid", "p_player_id" "uuid", "p_action" "text", "p_target_sector_id" "uuid", "p_target_planet_id" "uuid", "p_credits_before" bigint, "p_credits_after" bigint, "p_turns_before" integer, "p_turns_after" integer, "p_outcome" "text", "p_message" "text") RETURNS "void"
    LANGUAGE "sql"
    AS $$
  INSERT INTO public.ai_action_log (
    universe_id, player_id, action, target_sector_id, target_planet_id,
    credits_before, credits_after, turns_before, turns_after, outcome, message
  ) VALUES (
    p_universe_id, p_player_id, p_action, p_target_sector_id, p_target_planet_id,
    p_credits_before, p_credits_after, p_turns_before, p_turns_after, p_outcome, p_message
  );
$$;


ALTER FUNCTION "public"."log_ai_action"("p_universe_id" "uuid", "p_player_id" "uuid", "p_action" "text", "p_target_sector_id" "uuid", "p_target_planet_id" "uuid", "p_credits_before" bigint, "p_credits_after" bigint, "p_turns_before" integer, "p_turns_after" integer, "p_outcome" "text", "p_message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_ai_debug"("p_player_id" "uuid", "p_universe_id" "uuid", "p_step" "text", "p_data" "jsonb" DEFAULT NULL::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Log to a temporary table for debugging
  INSERT INTO public.ai_action_log (
    player_id,
    universe_id,
    action_type,
    action_data,
    success,
    message,
    created_at
  ) VALUES (
    p_player_id,
    p_universe_id,
    p_step,
    p_data,
    true,
    'Debug: ' || p_step,
    NOW()
  );
EXCEPTION WHEN OTHERS THEN
  -- Ignore logging errors
  NULL;
END;
$$;


ALTER FUNCTION "public"."log_ai_debug"("p_player_id" "uuid", "p_universe_id" "uuid", "p_step" "text", "p_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_cron_event"("p_universe_id" "uuid", "p_event_type" "text", "p_event_name" "text", "p_status" "text", "p_message" "text" DEFAULT NULL::"text", "p_execution_time_ms" integer DEFAULT NULL::integer, "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_log_id uuid;
BEGIN
    INSERT INTO public.cron_logs (
        universe_id,
        event_type,
        event_name,
        status,
        message,
        execution_time_ms,
        metadata
    ) VALUES (
        p_universe_id,
        p_event_type,
        p_event_name,
        p_status,
        p_message,
        p_execution_time_ms,
        p_metadata
    ) RETURNING id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$;


ALTER FUNCTION "public"."log_cron_event"("p_universe_id" "uuid", "p_event_type" "text", "p_event_name" "text", "p_status" "text", "p_message" "text", "p_execution_time_ms" integer, "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_sector_last_visited"("p_player_id" "uuid", "p_sector_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE public.sectors
    SET last_player_visited = p_player_id,
        last_visited_at = now()
    WHERE id = p_sector_id;
END;
$$;


ALTER FUNCTION "public"."mark_sector_last_visited"("p_player_id" "uuid", "p_sector_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."purchase_special_port_items"("p_player_id" "uuid", "p_purchases" "jsonb") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  purchase_item jsonb;
  total_cost bigint := 0;
  item_cost bigint;
  ship_credits bigint;
  remaining_credits bigint;
  v_ship RECORD;
BEGIN
  -- Get current ship data
  SELECT * INTO v_ship
  FROM ships
  WHERE player_id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Ship not found');
  END IF;
  
  -- Calculate total cost
  FOR purchase_item IN SELECT * FROM jsonb_array_elements(p_purchases)
  LOOP
    item_cost := (purchase_item->>'quantity')::integer * (purchase_item->>'cost')::integer;
    total_cost := total_cost + item_cost;
  END LOOP;
  
  -- Check if player has enough credits
  IF v_ship.credits < total_cost THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient credits');
  END IF;
  
  -- Process each purchase
  FOR purchase_item IN SELECT * FROM jsonb_array_elements(p_purchases)
  LOOP
    item_cost := (purchase_item->>'quantity')::integer * (purchase_item->>'cost')::integer;
    
    -- Update ship based on item type
    IF purchase_item->>'type' = 'upgrade' THEN
      -- Handle upgrades (this would need to be expanded based on upgrade types)
      UPDATE ships 
      SET credits = credits - item_cost
      WHERE player_id = p_player_id;
    ELSIF purchase_item->>'type' = 'device' THEN
      -- Handle device purchases
      UPDATE ships 
      SET 
        credits = credits - item_cost,
        device_space_beacons = CASE WHEN purchase_item->>'name' = 'Space Beacons' 
          THEN device_space_beacons + (purchase_item->>'quantity')::integer 
          ELSE device_space_beacons END,
        device_warp_editors = CASE WHEN purchase_item->>'name' = 'Warp Editors' 
          THEN device_warp_editors + (purchase_item->>'quantity')::integer 
          ELSE device_warp_editors END,
        device_genesis_torpedoes = CASE WHEN purchase_item->>'name' = 'Genesis Torpedoes' 
          THEN device_genesis_torpedoes + (purchase_item->>'quantity')::integer 
          ELSE device_genesis_torpedoes END,
        device_mine_deflectors = CASE WHEN purchase_item->>'name' = 'Mine Deflectors' 
          THEN device_mine_deflectors + (purchase_item->>'quantity')::integer 
          ELSE device_mine_deflectors END,
        device_emergency_warp = CASE WHEN purchase_item->>'name' = 'Emergency Warp Device' 
          THEN true ELSE device_emergency_warp END,
        device_escape_pod = CASE WHEN purchase_item->>'name' = 'Escape Pod' 
          THEN true ELSE device_escape_pod END,
        device_fuel_scoop = CASE WHEN purchase_item->>'name' = 'Fuel Scoop' 
          THEN true ELSE device_fuel_scoop END,
        device_last_seen = CASE WHEN purchase_item->>'name' = 'Last Ship Seen Device' 
          THEN true ELSE device_last_seen END
      WHERE player_id = p_player_id;
    ELSIF purchase_item->>'type' = 'item' THEN
      -- Handle item purchases with proper constraint validation
      UPDATE ships 
      SET 
        credits = credits - item_cost,
        colonists = CASE WHEN purchase_item->>'name' = 'Colonists' 
          THEN LEAST(colonists + (purchase_item->>'quantity')::integer, 100 * POWER(1.5, hull_lvl)) -- Cap at BNT hull capacity
          ELSE colonists END,
        fighters = CASE WHEN purchase_item->>'name' = 'Fighters' 
          THEN fighters + (purchase_item->>'quantity')::integer 
          ELSE fighters END,
        torpedoes = CASE WHEN purchase_item->>'name' = 'Torpedoes' 
          THEN torpedoes + (purchase_item->>'quantity')::integer 
          ELSE torpedoes END,
        armor = CASE WHEN purchase_item->>'name' = 'Armor Points' 
          THEN LEAST(COALESCE(armor, 0) + (purchase_item->>'quantity')::integer, 100 * POWER(1.5, armor_lvl)) -- Cap at armor capacity
          ELSE COALESCE(armor, 0) END
      WHERE player_id = p_player_id;
    END IF;
  END LOOP;
  
  -- Get remaining credits
  SELECT credits INTO remaining_credits
  FROM ships
  WHERE player_id = p_player_id;
  
  RETURN json_build_object(
    'success', true,
    'total_cost', total_cost,
    'remaining_credits', remaining_credits
  );
END;
$$;


ALTER FUNCTION "public"."purchase_special_port_items"("p_player_id" "uuid", "p_purchases" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_all_player_scores"("p_universe_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE public.players
  SET score = calculate_player_score(id)
  WHERE universe_id = p_universe_id;
END;
$$;


ALTER FUNCTION "public"."refresh_all_player_scores"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."regen_turns_for_universe"("p_universe_id" "uuid") RETURNS TABLE("players_updated" integer, "total_turns_generated" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_players_updated INTEGER := 0;
  v_total_turns_generated INTEGER := 0;
  v_turn_cap INTEGER;
BEGIN
  -- Get the turn cap from universe settings
  SELECT max_accumulated_turns INTO v_turn_cap
  FROM public.universe_settings
  WHERE universe_id = p_universe_id;
  
  -- If no universe settings found, use default
  IF v_turn_cap IS NULL THEN
    v_turn_cap := 5000; -- Default from universe_settings schema
  END IF;
  
  -- Add +1 turn to players with turns < turn_cap
  WITH updated_players AS (
    UPDATE public.players 
    SET 
      turns = LEAST(turns + 1, v_turn_cap),
      last_turn_ts = NOW()
    WHERE 
      universe_id = p_universe_id 
      AND turns < v_turn_cap
    RETURNING id, (LEAST(turns + 1, v_turn_cap) - turns) as turns_added
  )
  SELECT 
    COUNT(*)::INTEGER,
    COALESCE(SUM(turns_added), 0)::INTEGER
  INTO v_players_updated, v_total_turns_generated
  FROM updated_players;
  
  -- Return the results
  RETURN QUERY SELECT v_players_updated, v_total_turns_generated;
END;
$$;


ALTER FUNCTION "public"."regen_turns_for_universe"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_mines_from_sector"("p_sector_id" "uuid", "p_universe_id" "uuid", "p_player_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_removed_count integer;
BEGIN
    -- Remove mines (optionally only by specific player)
    IF p_player_id IS NOT NULL THEN
        DELETE FROM public.mines
        WHERE sector_id = p_sector_id 
          AND universe_id = p_universe_id
          AND deployed_by = p_player_id
        RETURNING id INTO v_removed_count;
    ELSE
        DELETE FROM public.mines
        WHERE sector_id = p_sector_id 
          AND universe_id = p_universe_id
        RETURNING id INTO v_removed_count;
    END IF;
    
    RETURN jsonb_build_object(
        'success', true,
        'mines_removed', v_removed_count
    );
END;
$$;


ALTER FUNCTION "public"."remove_mines_from_sector"("p_sector_id" "uuid", "p_universe_id" "uuid", "p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rename_planet"("p_user_id" "uuid", "p_planet_id" "uuid", "p_new_name" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player_id UUID;
    v_planet RECORD;
    v_result JSON;
BEGIN
    -- Validate input
    IF p_new_name IS NULL OR TRIM(p_new_name) = '' THEN
        RETURN json_build_object('error', json_build_object('code', 'invalid_input', 'message', 'Planet name cannot be empty'));
    END IF;
    
    IF LENGTH(TRIM(p_new_name)) > 50 THEN
        RETURN json_build_object('error', json_build_object('code', 'invalid_input', 'message', 'Planet name cannot exceed 50 characters'));
    END IF;
    
    -- Get player info
    SELECT p.id INTO v_player_id
    FROM players p 
    WHERE p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Player not found'));
    END IF;
    
    -- Get planet info and verify ownership
    SELECT * INTO v_planet
    FROM planets pl
    WHERE pl.id = p_planet_id AND pl.owner_player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Planet not found or not owned by player'));
    END IF;
    
    -- Update planet name
    UPDATE planets
    SET name = TRIM(p_new_name)
    WHERE id = p_planet_id;
    
    v_result := json_build_object(
        'success', TRUE,
        'message', 'Planet renamed successfully',
        'planet_id', p_planet_id,
        'new_name', TRIM(p_new_name)
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', json_build_object('code', 'internal_error', 'message', 'Failed to rename planet'));
END;
$$;


ALTER FUNCTION "public"."rename_planet"("p_user_id" "uuid", "p_planet_id" "uuid", "p_new_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rename_sector"("p_sector_id" "uuid", "p_player_id" "uuid", "p_new_name" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_sector RECORD;
BEGIN
  -- Get sector info
  SELECT id, number, owner_player_id, name
  INTO v_sector
  FROM public.sectors
  WHERE id = p_sector_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'sector_not_found');
  END IF;

  -- Federation sectors cannot be renamed
  IF v_sector.number BETWEEN 0 AND 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'federation_sector', 'message', 'Federation sectors cannot be renamed');
  END IF;

  -- Only the owner can rename
  IF v_sector.owner_player_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'sector_not_owned', 'message', 'You must own this sector to rename it');
  END IF;

  IF v_sector.owner_player_id != p_player_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_owner', 'message', 'Only the sector owner can rename it');
  END IF;

  -- Validate name
  IF p_new_name IS NULL OR LENGTH(TRIM(p_new_name)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_name', 'message', 'Sector name cannot be empty');
  END IF;

  IF LENGTH(p_new_name) > 50 THEN
    RETURN jsonb_build_object('success', false, 'error', 'name_too_long', 'message', 'Sector name must be 50 characters or less');
  END IF;

  -- Update sector name
  UPDATE public.sectors
  SET name = TRIM(p_new_name)
  WHERE id = p_sector_id;

  RETURN jsonb_build_object('success', true, 'name', TRIM(p_new_name));
END;
$$;


ALTER FUNCTION "public"."rename_sector"("p_sector_id" "uuid", "p_player_id" "uuid", "p_new_name" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rename_sector"("p_sector_id" "uuid", "p_player_id" "uuid", "p_new_name" "text") IS 'Allows sector owner to rename their sector';



CREATE OR REPLACE FUNCTION "public"."run_ai_actions_working"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_player record;
  v_decision text;
  v_result boolean;
  v_actions_taken int := 0;
  v_players_processed int := 0;
  v_trades int := 0;
  v_upgrades int := 0;
  v_planets_claimed int := 0;
  v_explorations int := 0;
  v_waits int := 0;
  v_errors int := 0;
  v_total_ai int := 0;
  v_ai_with_turns int := 0;
BEGIN
  -- Count AI players
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  -- Process each AI player (limit to 3 for testing)
  FOR v_player IN 
    SELECT 
      p.id as player_id,
      p.user_id,
      p.handle,
      p.turns,
      s.credits,
      s.hull
    FROM public.players p
    JOIN public.ships s ON s.player_id = p.id
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = true
      AND COALESCE(p.turns, 0) > 0
    ORDER BY p.turns DESC, s.credits DESC
    LIMIT 3 -- Process only 3 AI players for testing
  LOOP
    v_players_processed := v_players_processed + 1;
    
    BEGIN
      -- Make a simple decision based on credits and turns
      IF v_player.credits >= 1000 AND v_player.turns > 0 THEN
        v_decision := 'explore'; -- Simple action for testing
      ELSE
        v_decision := 'wait';
      END IF;
      
      -- Execute action (simplified for testing)
      IF v_decision = 'explore' THEN
        -- For now, just mark as successful without actual movement
        v_result := true;
        v_explorations := v_explorations + 1;
      ELSE
        v_result := true;
        v_waits := v_waits + 1;
      END IF;
      
      IF v_result THEN
        v_actions_taken := v_actions_taken + 1;
      ELSE
        v_errors := v_errors + 1;
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'ok',
    'ai_total', v_total_ai,
    'ai_with_turns', v_ai_with_turns,
    'ai_with_goal', v_total_ai,
    'players_processed', v_players_processed,
    'actions_taken', v_actions_taken,
    'trades', v_trades,
    'upgrades', v_upgrades,
    'planets_claimed', v_planets_claimed,
    'explorations', v_explorations,
    'waits', v_waits,
    'errors', v_errors
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'message', 'Failed to run AI player actions: ' || SQLERRM,
    'ai_total', 0,
    'ai_with_turns', 0,
    'ai_with_goal', 0,
    'players_processed', 0,
    'actions_taken', 0,
    'trades', 0,
    'upgrades', 0,
    'planets_claimed', 0,
    'explorations', 0,
    'waits', 0,
    'errors', 1
  );
END;
$$;


ALTER FUNCTION "public"."run_ai_actions_working"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_ai_player_actions"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_player record;
  v_decision text;
  v_result boolean;
  v_actions_taken int := 0;
  v_players_processed int := 0;
  v_trades int := 0;
  v_upgrades int := 0;
  v_planets_claimed int := 0;
  v_explorations int := 0;
  v_waits int := 0;
  v_errors int := 0;
  v_total_ai int := 0;
  v_ai_with_turns int := 0;
BEGIN
  -- Count AI players
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  -- Process each AI player
  FOR v_player IN 
    SELECT 
      p.id as player_id,
      p.user_id,
      p.handle,
      p.turns,
      s.credits,
      s.hull
    FROM public.players p
    JOIN public.ships s ON s.player_id = p.id
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = true
      AND COALESCE(p.turns, 0) > 0
    ORDER BY p.turns DESC, s.credits DESC -- Process AI with most resources first
  LOOP
    v_players_processed := v_players_processed + 1;
    
    BEGIN
      -- Make decision
      v_decision := ai_make_decision(v_player.player_id);
      
      -- Execute action
      v_result := ai_execute_action(v_player.player_id, p_universe_id, v_decision);
      
      IF v_result THEN
        v_actions_taken := v_actions_taken + 1;
        
        -- Track action types
        CASE v_decision
          WHEN 'trade', 'emergency_trade' THEN 
            v_trades := v_trades + 1;
          WHEN 'upgrade_ship' THEN 
            v_upgrades := v_upgrades + 1;
          WHEN 'claim_planet' THEN 
            v_planets_claimed := v_planets_claimed + 1;
          WHEN 'explore' THEN 
            v_explorations := v_explorations + 1;
          WHEN 'wait' THEN 
            v_waits := v_waits + 1;
        END CASE;
      ELSE
        v_errors := v_errors + 1;
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;
  
  -- Return comprehensive results
  RETURN jsonb_build_object(
    'success', true,
    'message', 'AI actions completed',
    'players_processed', v_players_processed,
    'actions_taken', v_actions_taken,
    'trades', v_trades,
    'upgrades', v_upgrades,
    'planets_claimed', v_planets_claimed,
    'explorations', v_explorations,
    'waits', v_waits,
    'errors', v_errors,
    'total_ai_players', v_total_ai,
    'ai_with_turns', v_ai_with_turns,
    'success_rate', CASE WHEN v_players_processed > 0 THEN 
      ROUND((v_actions_taken::numeric / v_players_processed::numeric) * 100, 2) 
    ELSE 0 END
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Failed to run AI player actions: ' || SQLERRM,
    'players_processed', v_players_processed,
    'actions_taken', v_actions_taken
  );
END;
$$;


ALTER FUNCTION "public"."run_ai_player_actions"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_ai_player_actions_debug"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_player record;
  v_decision text;
  v_result boolean;
  v_actions_taken int := 0;
  v_players_processed int := 0;
  v_trades int := 0;
  v_upgrades int := 0;
  v_planets_claimed int := 0;
  v_explorations int := 0;
  v_waits int := 0;
  v_errors int := 0;
  v_total_ai int := 0;
  v_ai_with_turns int := 0;
  v_debug_info jsonb;
BEGIN
  -- Log start of AI processing
  PERFORM log_ai_debug(NULL, p_universe_id, 'ai_processing_start', 
    jsonb_build_object('universe_id', p_universe_id));
  
  -- Count AI players
  SELECT COUNT(*) INTO v_total_ai
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true;
  
  SELECT COUNT(*) INTO v_ai_with_turns
  FROM public.players p
  WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
  
  -- Log counts
  PERFORM log_ai_debug(NULL, p_universe_id, 'ai_counts', 
    jsonb_build_object('total_ai', v_total_ai, 'ai_with_turns', v_ai_with_turns));
  
  -- Process each AI player
  FOR v_player IN 
    SELECT 
      p.id as player_id,
      p.user_id,
      p.handle,
      p.turns,
      s.credits,
      s.hull
    FROM public.players p
    JOIN public.ships s ON s.player_id = p.id
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = true
      AND COALESCE(p.turns, 0) > 0
    ORDER BY p.turns DESC, s.credits DESC -- Process AI with most resources first
  LOOP
    v_players_processed := v_players_processed + 1;
    
    -- Log player being processed
    PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'processing_player', 
      jsonb_build_object(
        'handle', v_player.handle,
        'turns', v_player.turns,
        'credits', v_player.credits,
        'hull', v_player.hull
      ));
    
    BEGIN
      -- Make decision
      v_decision := ai_make_decision_debug(v_player.player_id, p_universe_id);
      
      -- Log decision
      PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'decision_made', 
        jsonb_build_object('decision', v_decision));
      
      -- Execute action
      v_result := ai_execute_action(v_player.player_id, p_universe_id, v_decision);
      
      -- Log execution result
      PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'action_executed', 
        jsonb_build_object('decision', v_decision, 'success', v_result));
      
      IF v_result THEN
        v_actions_taken := v_actions_taken + 1;
        
        -- Track action type for stats
        CASE v_decision
          WHEN 'trade' THEN v_trades := v_trades + 1;
          WHEN 'upgrade_ship' THEN v_upgrades := v_upgrades + 1;
          WHEN 'claim_planet' THEN v_planets_claimed := v_planets_claimed + 1;
          WHEN 'explore' THEN v_explorations := v_explorations + 1;
          WHEN 'wait' THEN v_waits := v_waits + 1;
          ELSE NULL;
        END CASE;
      ELSE
        v_errors := v_errors + 1;
        PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'action_failed', 
          jsonb_build_object('decision', v_decision));
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      PERFORM log_ai_debug(v_player.player_id, p_universe_id, 'player_error', 
        jsonb_build_object('error', SQLERRM));
    END;
  END LOOP;
  
  -- Log final results
  PERFORM log_ai_debug(NULL, p_universe_id, 'ai_processing_complete', 
    jsonb_build_object(
      'players_processed', v_players_processed,
      'actions_taken', v_actions_taken,
      'trades', v_trades,
      'upgrades', v_upgrades,
      'planets_claimed', v_planets_claimed,
      'explorations', v_explorations,
      'waits', v_waits,
      'errors', v_errors
    ));
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'ok',
    'ai_total', v_total_ai,
    'ai_with_turns', v_ai_with_turns,
    'ai_with_goal', v_total_ai, -- All AI have goals
    'players_processed', v_players_processed,
    'actions_taken', v_actions_taken,
    'trades', v_trades,
    'upgrades', v_upgrades,
    'planets_claimed', v_planets_claimed,
    'explorations', v_explorations,
    'waits', v_waits,
    'errors', v_errors
  );
EXCEPTION WHEN OTHERS THEN
  PERFORM log_ai_debug(NULL, p_universe_id, 'ai_processing_error', 
    jsonb_build_object('error', SQLERRM));
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Failed to run AI player actions: ' || SQLERRM
  );
END;
$$;


ALTER FUNCTION "public"."run_ai_player_actions_debug"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_apocalypse_tick"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- TODO: Implement planetary apocalypse logic
    -- This should handle random planetary destruction events
    
    RETURN jsonb_build_object(
        'message', 'Planetary apocalypse placeholder - not yet implemented',
        'universe_id', p_universe_id,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."run_apocalypse_tick"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_defenses_checks"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- TODO: Implement defenses check logic
    -- This should check sector defenses, update fighter counts, etc.
    
    RETURN jsonb_build_object(
        'message', 'Defenses check placeholder - not yet implemented',
        'universe_id', p_universe_id,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."run_defenses_checks"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_enhanced_ai_actions"("p_universe_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    ai_player RECORD;
    ai_memory RECORD;
    actions_taken INTEGER := 0;
    v_result JSON;
    v_decision TEXT;
    v_action_result BOOLEAN;
BEGIN
    -- Process each AI player
    FOR ai_player IN 
        SELECT p.id, p.handle as name, p.ai_personality, 
               s.id as ship_id, s.credits, p.current_sector as sector_id, s.ore, s.organics, s.goods, s.energy, s.colonists,
               s.hull_lvl, s.engine_lvl, s.power_lvl, s.comp_lvl, s.sensor_lvl, s.beam_lvl,
               s.armor_lvl, s.cloak_lvl, s.torp_launcher_lvl, s.shield_lvl, s.fighters, s.torpedoes,
               sec.number as sector_number, sec.universe_id
        FROM public.players p
        JOIN public.ships s ON p.id = s.player_id
        JOIN public.sectors sec ON p.current_sector = sec.id
        WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
    LOOP
        -- Get or create AI memory
        SELECT * INTO ai_memory FROM ai_player_memory WHERE player_id = ai_player.id;
        
        IF NOT FOUND THEN
            INSERT INTO ai_player_memory (player_id, current_goal)
            VALUES (ai_player.id, 'explore')
            RETURNING * INTO ai_memory;
        END IF;
        
        -- Make decisions based on current situation (simplified logic)
        v_decision := public.ai_make_simple_decision(ai_player, ai_memory);
        
        -- Execute the decision using REAL player functions
        v_action_result := public.ai_execute_real_action(ai_player, ai_memory, v_decision);
        
        IF v_action_result THEN
            actions_taken := actions_taken + 1;
        END IF;
        
        -- Update AI memory
        UPDATE ai_player_memory 
        SET last_action = NOW(), 
            updated_at = NOW()
        WHERE player_id = ai_player.id;
    END LOOP;
    
    v_result := json_build_object(
        'success', TRUE,
        'message', 'Enhanced AI actions completed',
        'actions_taken', actions_taken,
        'universe_id', p_universe_id
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', 'Failed to run enhanced AI actions: ' || SQLERRM);
END;
$$;


ALTER FUNCTION "public"."run_enhanced_ai_actions"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_planet_production"("p_universe_id" "uuid") RETURNS TABLE("planets_processed" integer, "colonists_grown" integer, "resources_produced" integer, "credits_produced" integer, "interest_generated" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    planet_record RECORD;
    v_settings RECORD;
    v_growth_rate DECIMAL;
    v_new_colonists BIGINT;
    v_production_colonists BIGINT;
    v_total_allocation INTEGER;
    v_remaining_percent INTEGER;
    v_produced_ore BIGINT;
    v_produced_organics BIGINT;
    v_produced_goods BIGINT;
    v_produced_energy BIGINT;
    v_produced_fighters BIGINT;
    v_produced_torpedoes BIGINT;
    v_produced_credits BIGINT;
    v_interest_generated BIGINT;
    v_planets_processed INTEGER := 0;
    v_colonists_grown INTEGER := 0;
    v_resources_produced INTEGER := 0;
    v_credits_produced INTEGER := 0;
    v_total_interest_generated INTEGER := 0;
BEGIN
    -- Get universe settings
    SELECT 
        colonist_production_rate,
        colonists_per_ore,
        colonists_per_organics,
        colonists_per_goods,
        colonists_per_energy,
        colonists_per_fighter,
        colonists_per_torpedo,
        colonists_per_credits,
        planet_interest_rate
    INTO v_settings
    FROM universe_settings 
    WHERE universe_id = p_universe_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Universe settings not found for universe %', p_universe_id;
    END IF;
    
    v_growth_rate := v_settings.colonist_production_rate;
    
    -- Process each planet
    FOR planet_record IN 
        SELECT 
            p.id, 
            p.colonists, 
            p.colonists_max, 
            p.ore, 
            p.organics, 
            p.goods, 
            p.energy,
            p.fighters,
            p.torpedoes,
            p.production_ore_percent,
            p.production_organics_percent,
            p.production_goods_percent,
            p.production_energy_percent,
            p.production_fighters_percent,
            p.production_torpedoes_percent,
            p.owner_player_id,
            p.last_colonist_growth, 
            p.last_production,
            p.credits
        FROM planets p
        WHERE p.owner_player_id IS NOT NULL
    LOOP
        v_planets_processed := v_planets_processed + 1;
        
        -- Colonist growth (if not at max) - FIXED: Use safer calculation
        IF planet_record.colonists < planet_record.colonists_max THEN
            -- Calculate growth more safely to avoid integer overflow
            v_new_colonists := planet_record.colonists + 
                LEAST(
                    planet_record.colonists_max - planet_record.colonists,
                    GREATEST(1, FLOOR(planet_record.colonists * v_growth_rate))
                );
            
            -- Ensure we don't exceed the max
            v_new_colonists := LEAST(v_new_colonists, planet_record.colonists_max);
            
            IF v_new_colonists > planet_record.colonists THEN
                v_colonists_grown := v_colonists_grown + 1;
                
                UPDATE planets 
                SET colonists = v_new_colonists,
                    last_colonist_growth = now()
                WHERE id = planet_record.id;
            END IF;
        END IF;
        
        -- Calculate production based on allocation percentages
        -- Only produce if colonists > 0 and allocation percentages are set
        IF planet_record.colonists > 0 THEN
            -- Calculate total allocation percentage
            v_total_allocation := COALESCE(planet_record.production_ore_percent, 0) +
                                 COALESCE(planet_record.production_organics_percent, 0) +
                                 COALESCE(planet_record.production_goods_percent, 0) +
                                 COALESCE(planet_record.production_energy_percent, 0) +
                                 COALESCE(planet_record.production_fighters_percent, 0) +
                                 COALESCE(planet_record.production_torpedoes_percent, 0);
            
            -- Calculate remaining percentage for credits
            v_remaining_percent := 100 - v_total_allocation;
            
            -- Calculate production for each resource based on allocation
            IF planet_record.production_ore_percent > 0 THEN
                v_production_colonists := FLOOR(planet_record.colonists * planet_record.production_ore_percent / 100.0);
                v_produced_ore := FLOOR(v_production_colonists / v_settings.colonists_per_ore);
            ELSE
                v_produced_ore := 0;
            END IF;
            
            IF planet_record.production_organics_percent > 0 THEN
                v_production_colonists := FLOOR(planet_record.colonists * planet_record.production_organics_percent / 100.0);
                v_produced_organics := FLOOR(v_production_colonists / v_settings.colonists_per_organics);
            ELSE
                v_produced_organics := 0;
            END IF;
            
            IF planet_record.production_goods_percent > 0 THEN
                v_production_colonists := FLOOR(planet_record.colonists * planet_record.production_goods_percent / 100.0);
                v_produced_goods := FLOOR(v_production_colonists / v_settings.colonists_per_goods);
            ELSE
                v_produced_goods := 0;
            END IF;
            
            IF planet_record.production_energy_percent > 0 THEN
                v_production_colonists := FLOOR(planet_record.colonists * planet_record.production_energy_percent / 100.0);
                v_produced_energy := FLOOR(v_production_colonists / v_settings.colonists_per_energy);
            ELSE
                v_produced_energy := 0;
            END IF;
            
            IF planet_record.production_fighters_percent > 0 THEN
                v_production_colonists := FLOOR(planet_record.colonists * planet_record.production_fighters_percent / 100.0);
                v_produced_fighters := FLOOR(v_production_colonists / v_settings.colonists_per_fighter);
            ELSE
                v_produced_fighters := 0;
            END IF;
            
            IF planet_record.production_torpedoes_percent > 0 THEN
                v_production_colonists := FLOOR(planet_record.colonists * planet_record.production_torpedoes_percent / 100.0);
                v_produced_torpedoes := FLOOR(v_production_colonists / v_settings.colonists_per_torpedo);
            ELSE
                v_produced_torpedoes := 0;
            END IF;
            
            -- Calculate credits production from remaining colonists
            IF v_remaining_percent > 0 THEN
                v_production_colonists := FLOOR(planet_record.colonists * v_remaining_percent / 100.0);
                v_produced_credits := FLOOR(v_production_colonists / v_settings.colonists_per_credits);
            ELSE
                v_produced_credits := 0;
            END IF;
            
            -- Calculate interest on existing planet credits
            v_interest_generated := FLOOR(planet_record.credits * v_settings.planet_interest_rate / 100.0);
            
            -- Update planet resources
            UPDATE planets 
            SET 
                ore = ore + v_produced_ore,
                organics = organics + v_produced_organics,
                goods = goods + v_produced_goods,
                energy = energy + v_produced_energy,
                fighters = fighters + v_produced_fighters,
                torpedoes = torpedoes + v_produced_torpedoes,
                credits = credits + v_produced_credits + v_interest_generated,
                last_production = now()
            WHERE id = planet_record.id;
            
            -- Update counters
            v_resources_produced := v_resources_produced + 1;
            v_credits_produced := v_credits_produced + v_produced_credits;
            v_total_interest_generated := v_total_interest_generated + v_interest_generated;
        END IF;
    END LOOP;
    
    -- Return results
    RETURN QUERY SELECT 
        v_planets_processed,
        v_colonists_grown,
        v_resources_produced,
        v_credits_produced,
        v_total_interest_generated;
END;
$$;


ALTER FUNCTION "public"."run_planet_production"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_xenobes_turn"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- TODO: Implement xenobes AI logic
    -- This should handle xenobe ship movements, attacks, etc.
    
    RETURN jsonb_build_object(
        'message', 'Xenobes play placeholder - not yet implemented',
        'universe_id', p_universe_id,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."run_xenobes_turn"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."simple_ai_debug"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_total_ai int;
  v_ai_with_turns int;
  v_error_msg text;
BEGIN
  BEGIN
    -- Count AI players
    SELECT COUNT(*) INTO v_total_ai
    FROM public.players p
    WHERE p.universe_id = p_universe_id AND p.is_ai = true;
    
    -- Count AI players with turns
    SELECT COUNT(*) INTO v_ai_with_turns
    FROM public.players p
    WHERE p.universe_id = p_universe_id AND p.is_ai = true AND COALESCE(p.turns, 0) > 0;
    
    RETURN jsonb_build_object(
      'success', true,
      'message', 'ok',
      'ai_total', v_total_ai,
      'ai_with_turns', v_ai_with_turns,
      'ai_with_goal', v_total_ai,
      'actions_taken', 0,
      'players_processed', 0,
      'planets_claimed', 0,
      'upgrades', 0,
      'trades', 0,
      'universe_id', p_universe_id
    );
    
  EXCEPTION WHEN OTHERS THEN
    v_error_msg := SQLERRM;
    RETURN jsonb_build_object(
      'success', false,
      'message', v_error_msg,
      'ai_total', 0,
      'ai_with_turns', 0,
      'ai_with_goal', 0,
      'actions_taken', 0,
      'players_processed', 0,
      'planets_claimed', 0,
      'upgrades', 0,
      'trades', 0,
      'universe_id', p_universe_id
    );
  END;
END;
$$;


ALTER FUNCTION "public"."simple_ai_debug"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_ai_debug_system"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Clear old debug logs first
  DELETE FROM public.ai_action_log 
  WHERE universe_id = p_universe_id 
    AND action_type LIKE 'Debug:%'
    AND created_at < NOW() - INTERVAL '1 hour';
  
  -- Run the debug AI system
  SELECT run_ai_player_actions_debug(p_universe_id) INTO v_result;
  
  -- Return both the result and a summary of logs
  RETURN jsonb_build_object(
    'ai_result', v_result,
    'debug_logs_count', (
      SELECT COUNT(*) 
      FROM public.ai_action_log 
      WHERE universe_id = p_universe_id 
        AND action_type LIKE 'Debug:%'
        AND created_at > NOW() - INTERVAL '5 minutes'
    )
  );
END;
$$;


ALTER FUNCTION "public"."test_ai_debug_system"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_cron_function"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Test the cron function directly
  SELECT cron_run_ai_actions_safe(p_universe_id) INTO v_result;
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."test_cron_function"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_destroy_response_format"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_universe_name TEXT := 'Test Universe';
  v_player_count INTEGER := 5;
  v_ship_count INTEGER := 5;
BEGIN
  -- Return the exact same format as destroy_universe
  RETURN jsonb_build_object(
    'ok', true,
    'universe_name', v_universe_name,
    'players_deleted', v_player_count,
    'ships_deleted', v_ship_count,
    'sectors_deleted', 100,
    'planets_deleted', 50,
    'ports_deleted', 25,
    'message', 'Universe destroyed successfully with all associated data'
  );
END;
$$;


ALTER FUNCTION "public"."test_destroy_response_format"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_destroy_universe"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_universe_name TEXT;
BEGIN
  -- Get universe name for logging (same as destroy function)
  SELECT name INTO v_universe_name FROM universes WHERE id = p_universe_id;
  
  IF v_universe_name IS NULL THEN
    RETURN jsonb_build_object('error', 'Universe not found');
  END IF;
  
  -- Return what we would return (without actually destroying)
  RETURN jsonb_build_object(
    'ok', true,
    'universe_name', v_universe_name,
    'message', 'Test successful - universe name found'
  );
END;
$$;


ALTER FUNCTION "public"."test_destroy_universe"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_diagnostic"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Test with the universe ID we've been using
  SELECT diagnose_ai_players('3c491d51-61e2-4969-ba3e-142d4f5747d8') INTO v_result;
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."test_diagnostic"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_enhanced_ai_debug"("p_universe_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    ai_player RECORD;
    ai_memory RECORD;
    actions_taken INTEGER := 0;
    v_decision TEXT;
    v_action_result BOOLEAN;
    v_debug_output TEXT := '';
BEGIN
    v_debug_output := v_debug_output || 'Starting enhanced AI debug for universe: ' || p_universe_id || E'\n';
    
    -- Process each AI player
    FOR ai_player IN 
        SELECT p.id, p.handle as name, p.ai_personality, 
               s.id as ship_id, s.credits, p.current_sector as sector_id, s.ore, s.organics, s.goods, s.energy, s.colonists,
               s.hull_lvl, s.engine_lvl, s.power_lvl, s.comp_lvl, s.sensor_lvl, s.beam_lvl,
               s.armor_lvl, s.cloak_lvl, s.torp_launcher_lvl, s.shield_lvl, s.fighters, s.torpedoes,
               sec.number as sector_number, sec.universe_id
        FROM public.players p
        JOIN public.ships s ON p.id = s.player_id
        JOIN public.sectors sec ON p.current_sector = sec.id
        WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
    LOOP
        v_debug_output := v_debug_output || 'Processing AI player: ' || ai_player.name || E'\n';
        
        -- Get or create AI memory
        SELECT * INTO ai_memory FROM ai_player_memory WHERE player_id = ai_player.id;
        
        IF NOT FOUND THEN
            v_debug_output := v_debug_output || 'Creating new memory for: ' || ai_player.name || E'\n';
            INSERT INTO ai_player_memory (player_id, current_goal)
            VALUES (ai_player.id, 'explore')
            RETURNING * INTO ai_memory;
        ELSE
            v_debug_output := v_debug_output || 'Found existing memory for: ' || ai_player.name || E'\n';
        END IF;
        
        -- Make decisions based on personality
        v_decision := public.ai_make_decision(ai_player, ai_memory);
        v_debug_output := v_debug_output || 'Decision for ' || ai_player.name || ': ' || v_decision || E'\n';
        
        -- Execute the decision
        v_action_result := public.ai_execute_action(ai_player, ai_memory, v_decision);
        v_debug_output := v_debug_output || 'Action result for ' || ai_player.name || ': ' || v_action_result || E'\n';
        
        IF v_action_result THEN
            actions_taken := actions_taken + 1;
            v_debug_output := v_debug_output || 'Action successful for ' || ai_player.name || E'\n';
        ELSE
            v_debug_output := v_debug_output || 'Action failed for ' || ai_player.name || E'\n';
        END IF;
        
        -- Update AI memory
        UPDATE ai_player_memory 
        SET last_action = NOW(), 
            updated_at = NOW()
        WHERE player_id = ai_player.id;
        
        v_debug_output := v_debug_output || 'Updated memory for ' || ai_player.name || E'\n';
    END LOOP;
    
    v_debug_output := v_debug_output || 'Total actions taken: ' || actions_taken || E'\n';
    RETURN v_debug_output;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN v_debug_output || 'ERROR: ' || SQLERRM;
END;
$$;


ALTER FUNCTION "public"."test_enhanced_ai_debug"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tow_ships_from_fed"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- TODO: Implement ship towing logic
    -- This should tow ships from federation sectors to neutral space
    
    RETURN jsonb_build_object(
        'message', 'Ships tow from fed placeholder - not yet implemented',
        'universe_id', p_universe_id,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."tow_ships_from_fed"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."track_sector_visit"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Only act when current_sector actually changes and is not null
  IF TG_OP = 'UPDATE' AND NEW.current_sector IS DISTINCT FROM OLD.current_sector AND NEW.current_sector IS NOT NULL THEN
    UPDATE public.sectors s
      SET last_visited_at = NOW(),
          last_visited_by = NEW.id
      WHERE s.universe_id = NEW.universe_id
        AND s.id = NEW.current_sector;  -- compare UUID to UUID
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."track_sector_visit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."track_turn_spent"("p_player_id" "uuid") RETURNS "void"
    LANGUAGE "sql"
    AS $$
  UPDATE public.players
  SET turns_spent = COALESCE(turns_spent, 0) + 1
  WHERE id = p_player_id;
$$;


ALTER FUNCTION "public"."track_turn_spent"("p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."track_turn_spent"("p_player_id" "uuid", "p_turns_spent" integer, "p_action_type" "text" DEFAULT 'unknown'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Validate inputs
    IF p_player_id IS NULL THEN
        RAISE EXCEPTION 'Player ID cannot be null';
    END IF;
    
    IF p_turns_spent IS NULL OR p_turns_spent <= 0 THEN
        RAISE EXCEPTION 'Turns spent must be a positive integer';
    END IF;
    
    -- Update turns_spent counter
    UPDATE public.players 
    SET turns_spent = turns_spent + p_turns_spent
    WHERE id = p_player_id;
    
    -- Log the action (optional - for debugging)
    RAISE NOTICE 'Player % spent % turns on action: %', p_player_id, p_turns_spent, p_action_type;
    
END;
$$;


ALTER FUNCTION "public"."track_turn_spent"("p_player_id" "uuid", "p_turns_spent" integer, "p_action_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trade_by_type"("p_user_id" "uuid", "p_port_id" "uuid", "p_resource" "text", "p_action" "text", "p_quantity" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_player players;
  v_ship ships;
  v_port ports;
  v_sector sectors;
  v_unit_price NUMERIC;
  v_total_cost NUMERIC;
  v_new_credits NUMERIC;
  v_new_cargo INTEGER;
  v_new_stock INTEGER;
  v_result JSONB;
BEGIN
  -- Load player, ship, port with proper universe validation
  SELECT * INTO v_player FROM players WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  SELECT p.* INTO v_port
  FROM ports p
  WHERE p.id = p_port_id FOR UPDATE;
  
  SELECT s.number as sector_number, s.universe_id INTO v_sector
  FROM sectors s
  JOIN ports p ON s.id = p.sector_id
  WHERE p.id = p_port_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Port not found'));
  END IF;

  -- Universe validation
  IF v_player.universe_id != v_sector.universe_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_mismatch', 'message', 'Port not in player universe'));
  END IF;

  -- Validate port type and action
  IF v_port.kind = 'special' THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_port_kind', 'message', 'Special ports do not trade commodities'));
  END IF;

  -- Validate resource
  IF p_resource NOT IN ('ore', 'organics', 'goods', 'energy') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_resource', 'message', 'Invalid resource type'));
  END IF;

  -- Validate action
  IF p_action NOT IN ('buy', 'sell') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_action', 'message', 'Invalid action'));
  END IF;

  -- Validate quantity
  IF p_quantity <= 0 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_quantity', 'message', 'Quantity must be positive'));
  END IF;

  -- Compute unit price using enhanced dynamic pricing
  DECLARE
    base_price NUMERIC;
    stock_level INTEGER;
    price_multiplier NUMERIC;
  BEGIN
    CASE p_resource
      WHEN 'ore' THEN 
        base_price := v_port.price_ore;
        stock_level := v_port.ore;
      WHEN 'organics' THEN 
        base_price := v_port.price_organics;
        stock_level := v_port.organics;
      WHEN 'goods' THEN 
        base_price := v_port.price_goods;
        stock_level := v_port.goods;
      WHEN 'energy' THEN 
        base_price := v_port.price_energy;
        stock_level := v_port.energy;
    END CASE;
    
    -- Apply enhanced dynamic pricing based on stock levels and port type
    price_multiplier := calculate_price_multiplier(stock_level, v_port.kind);
    v_unit_price := base_price * price_multiplier;
  END;

  -- Apply buy/sell multipliers
  IF p_action = 'buy' THEN
    v_unit_price := v_unit_price * 0.90; -- Player buys at 90% of dynamic price
  ELSE
    v_unit_price := v_unit_price * 1.10; -- Player sells at 110% of dynamic price
  END IF;

  v_total_cost := p_quantity * v_unit_price;

  -- Validate trade constraints
  IF p_action = 'buy' THEN
    -- Can only buy native commodity
    IF p_resource != v_port.kind THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_buy', 'message', 'Can only buy native commodity from this port'));
    END IF;
    
    -- Check stock availability
    CASE p_resource
      WHEN 'ore' THEN v_new_stock := v_port.ore - p_quantity;
      WHEN 'organics' THEN v_new_stock := v_port.organics - p_quantity;
      WHEN 'goods' THEN v_new_stock := v_port.goods - p_quantity;
      WHEN 'energy' THEN v_new_stock := v_port.energy - p_quantity;
    END CASE;
    
    IF v_new_stock < 0 THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_stock', 'message', 'Port does not have enough stock'));
    END IF;
    
    -- Check player credits
    IF v_player.credits < v_total_cost THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
    END IF;
    
    -- Check cargo space
    CASE p_resource
      WHEN 'ore' THEN v_new_cargo := v_ship.ore + p_quantity;
      WHEN 'organics' THEN v_new_cargo := v_ship.organics + p_quantity;
      WHEN 'goods' THEN v_new_cargo := v_ship.goods + p_quantity;
      WHEN 'energy' THEN v_new_cargo := v_ship.energy + p_quantity;
    END CASE;
    
    IF v_new_cargo > v_ship.cargo THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough cargo space'));
    END IF;
    
    v_new_credits := v_player.credits - v_total_cost;
    
  ELSE -- sell
    -- Can only sell non-native commodities
    IF p_resource = v_port.kind THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_sell', 'message', 'Cannot sell native commodity to its own port'));
    END IF;
    
    -- Check player stock
    CASE p_resource
      WHEN 'ore' THEN 
        IF v_ship.ore < p_quantity THEN
          RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough ore to sell'));
        END IF;
        v_new_cargo := v_ship.ore - p_quantity;
      WHEN 'organics' THEN 
        IF v_ship.organics < p_quantity THEN
          RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough organics to sell'));
        END IF;
        v_new_cargo := v_ship.organics - p_quantity;
      WHEN 'goods' THEN 
        IF v_ship.goods < p_quantity THEN
          RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough goods to sell'));
        END IF;
        v_new_cargo := v_ship.goods - p_quantity;
      WHEN 'energy' THEN 
        IF v_ship.energy < p_quantity THEN
          RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough energy to sell'));
        END IF;
        v_new_cargo := v_ship.energy - p_quantity;
    END CASE;
    
    v_new_credits := v_player.credits + v_total_cost;
    v_new_stock := stock_level + p_quantity; -- Port gains stock when player sells
  END IF;

  -- Execute the trade
  -- Update player credits
  UPDATE players SET credits = v_new_credits WHERE id = v_player.id;
  
  -- Update ship cargo
  CASE p_resource
    WHEN 'ore' THEN
      UPDATE ships SET ore = v_new_cargo WHERE id = v_ship.id;
      UPDATE ports SET ore = v_new_stock WHERE id = v_port.id;
    WHEN 'organics' THEN
      UPDATE ships SET organics = v_new_cargo WHERE id = v_ship.id;
      UPDATE ports SET organics = v_new_stock WHERE id = v_port.id;
    WHEN 'goods' THEN
      UPDATE ships SET goods = v_new_cargo WHERE id = v_ship.id;
      UPDATE ports SET goods = v_new_stock WHERE id = v_port.id;
    WHEN 'energy' THEN
      UPDATE ships SET energy = v_new_cargo WHERE id = v_ship.id;
      UPDATE ports SET energy = v_new_stock WHERE id = v_port.id;
  END CASE;

  -- Return success result
  v_result := jsonb_build_object(
    'success', true,
    'action', p_action,
    'resource', p_resource,
    'quantity', p_quantity,
    'unit_price', v_unit_price,
    'total_cost', v_total_cost,
    'new_credits', v_new_credits,
    'new_cargo', v_new_cargo,
    'new_stock', v_new_stock
  );

  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."trade_by_type"("p_user_id" "uuid", "p_port_id" "uuid", "p_resource" "text", "p_action" "text", "p_quantity" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trades_compat_sync"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Legacy -> New
  IF NEW.quantity IS NULL AND NEW.qty IS NOT NULL THEN
    NEW.quantity := NEW.qty;
  END IF;
  IF NEW.unit_price IS NULL AND NEW.price IS NOT NULL THEN
    NEW.unit_price := NEW.price;
  END IF;
  IF NEW.total_price IS NULL AND NEW.price IS NOT NULL THEN
    NEW.total_price := COALESCE(NEW.quantity, NEW.qty)::numeric * NEW.price;
  END IF;

  -- New -> Legacy (to satisfy NOT NULL on qty/price in some schemas)
  IF NEW.qty IS NULL AND NEW.quantity IS NOT NULL THEN
    NEW.qty := NEW.quantity;
  END IF;
  IF NEW.price IS NULL AND NEW.unit_price IS NOT NULL THEN
    NEW.price := NEW.unit_price;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trades_compat_sync"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_mark_last_visitor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.current_sector IS NOT NULL AND NEW.current_sector <> COALESCE(OLD.current_sector, '00000000-0000-0000-0000-000000000000') THEN
    UPDATE public.sectors
      SET last_player_visited = NEW.id,
          last_visited_at = now()
      WHERE id = NEW.current_sector;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_mark_last_visitor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_update_sector_ownership"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Check ownership for the affected sector
  IF TG_OP = 'DELETE' THEN
    PERFORM public.update_sector_ownership(OLD.sector_id);
  ELSE
    PERFORM public.update_sector_ownership(NEW.sector_id);
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_update_sector_ownership"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."universe_exists"("p_universe_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
BEGIN
  RETURN EXISTS(SELECT 1 FROM universes WHERE id = p_universe_id);
END;
$$;


ALTER FUNCTION "public"."universe_exists"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_ai_memory"("p_player_id" "uuid", "p_action" "text", "p_success" boolean, "p_message" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Update or insert AI memory
  INSERT INTO public.ai_player_memory (
    player_id, 
    current_goal, 
    last_action, 
    action_count,
    efficiency_score,
    updated_at
  ) VALUES (
    p_player_id,
    p_action,
    p_action,
    1,
    CASE WHEN p_success THEN 1.0 ELSE 0.0 END,
    NOW()
  )
  ON CONFLICT (player_id) 
  DO UPDATE SET
    current_goal = CASE WHEN p_success THEN p_action ELSE current_goal END,
    last_action = p_action,
    action_count = ai_player_memory.action_count + 1,
    efficiency_score = (ai_player_memory.efficiency_score * 0.9) + (CASE WHEN p_success THEN 0.1 ELSE 0.0 END),
    updated_at = NOW();
EXCEPTION WHEN OTHERS THEN
  -- Silently ignore memory update errors
  NULL;
END;
$$;


ALTER FUNCTION "public"."update_ai_memory"("p_player_id" "uuid", "p_action" "text", "p_success" boolean, "p_message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_player_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_planet RECORD;
  v_total_percent integer;
BEGIN
  -- Validate input percentages
  IF p_ore_percent < 0 OR p_ore_percent > 100 OR
     p_organics_percent < 0 OR p_organics_percent > 100 OR
     p_goods_percent < 0 OR p_goods_percent > 100 OR
     p_energy_percent < 0 OR p_energy_percent > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Percentages must be between 0 and 100');
  END IF;
  
  v_total_percent := p_ore_percent + p_organics_percent + p_goods_percent + p_energy_percent;
  
  IF v_total_percent > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Total allocation cannot exceed 100%');
  END IF;
  
  -- Get planet and verify ownership
  SELECT p.*, s.universe_id
  INTO v_planet
  FROM planets p
  JOIN sectors s ON s.id = p.sector_id
  WHERE p.id = p_planet_id AND p.owner_player_id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Planet not found or not owned by player');
  END IF;
  
  -- Update production allocation
  UPDATE planets 
  SET 
    production_ore_percent = p_ore_percent,
    production_organics_percent = p_organics_percent,
    production_goods_percent = p_goods_percent,
    production_energy_percent = p_energy_percent
  WHERE id = p_planet_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Production allocation updated successfully',
    'allocation', jsonb_build_object(
      'ore', p_ore_percent,
      'organics', p_organics_percent,
      'goods', p_goods_percent,
      'energy', p_energy_percent,
      'credits', 100 - v_total_percent
    )
  );
END;
$$;


ALTER FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_fighters_percent" integer, "p_torpedoes_percent" integer, "p_player_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_planet RECORD;
  v_total_percent integer;
BEGIN
  -- Validate input percentages
  IF p_ore_percent < 0 OR p_ore_percent > 100 OR
     p_organics_percent < 0 OR p_organics_percent > 100 OR
     p_goods_percent < 0 OR p_goods_percent > 100 OR
     p_energy_percent < 0 OR p_energy_percent > 100 OR
     p_fighters_percent < 0 OR p_fighters_percent > 100 OR
     p_torpedoes_percent < 0 OR p_torpedoes_percent > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Percentages must be between 0 and 100');
  END IF;
  
  v_total_percent := p_ore_percent + p_organics_percent + p_goods_percent + p_energy_percent + p_fighters_percent + p_torpedoes_percent;
  
  IF v_total_percent > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Total allocation cannot exceed 100%');
  END IF;
  
  -- Get planet and verify ownership
  SELECT p.*, s.universe_id
  INTO v_planet
  FROM planets p
  JOIN sectors s ON s.id = p.sector_id
  WHERE p.id = p_planet_id AND p.owner_player_id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Planet not found or not owned by player');
  END IF;
  
  -- Update production allocation
  UPDATE planets 
  SET 
    production_ore_percent = p_ore_percent,
    production_organics_percent = p_organics_percent,
    production_goods_percent = p_goods_percent,
    production_energy_percent = p_energy_percent,
    production_fighters_percent = p_fighters_percent,
    production_torpedoes_percent = p_torpedoes_percent
  WHERE id = p_planet_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Production allocation updated successfully',
    'allocation', jsonb_build_object(
      'ore', p_ore_percent,
      'organics', p_organics_percent,
      'goods', p_goods_percent,
      'energy', p_energy_percent,
      'fighters', p_fighters_percent,
      'torpedoes', p_torpedoes_percent,
      'credits', 100 - v_total_percent
    )
  );
END;
$$;


ALTER FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_fighters_percent" integer, "p_torpedoes_percent" integer, "p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_player_last_login"("p_player_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Update last_login timestamp for the player
    UPDATE public.players 
    SET last_login = NOW()
    WHERE id = p_player_id;
END;
$$;


ALTER FUNCTION "public"."update_player_last_login"("p_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_player_score"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_score BIGINT;
BEGIN
  -- Calculate score for the player
  v_score := calculate_player_score(NEW.id);
  
  -- Update the score column
  NEW.score := v_score;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_player_score"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_player_score_from_planet"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_score BIGINT;
BEGIN
  -- Update score for the old owner if there was one
  IF OLD.owner_player_id IS NOT NULL THEN
    v_score := calculate_player_score(OLD.owner_player_id);
    UPDATE public.players SET score = v_score WHERE id = OLD.owner_player_id;
  END IF;
  
  -- Update score for the new owner if there is one
  IF NEW.owner_player_id IS NOT NULL THEN
    v_score := calculate_player_score(NEW.owner_player_id);
    UPDATE public.players SET score = v_score WHERE id = NEW.owner_player_id;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_player_score_from_planet"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_player_score_from_ship"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_score BIGINT;
BEGIN
  -- Calculate score for the player who owns this ship
  v_score := calculate_player_score(NEW.player_id);
  
  -- Update the score in players table
  UPDATE public.players
  SET score = v_score
  WHERE id = NEW.player_id;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_player_score_from_ship"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_port_stock_dynamics"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  port_record RECORD;
  updated_count INTEGER := 0;
  decay_rate NUMERIC := 0.05; -- 5% decay for non-native commodities
  regen_rate NUMERIC := 0.10; -- 10% regeneration for native commodities
  native_stock INTEGER;
  native_cap INTEGER;
BEGIN
  -- Process each commodity port
  FOR port_record IN 
    SELECT * FROM ports WHERE kind IN ('ore', 'organics', 'goods', 'energy')
  LOOP
    -- Get port-type-specific base stock and cap
    CASE port_record.kind
      WHEN 'ore' THEN 
        native_stock := port_record.ore;
        native_cap := 100000000; -- 100M cap
      WHEN 'organics' THEN 
        native_stock := port_record.organics;
        native_cap := 100000000; -- 100M cap
      WHEN 'goods' THEN 
        native_stock := port_record.goods;
        native_cap := 100000000; -- 100M cap
      WHEN 'energy' THEN 
        native_stock := port_record.energy;
        native_cap := 1000000000; -- 1B cap
    END CASE;
    
    -- Update native commodity (regeneration towards cap)
    IF native_stock < native_cap THEN
      CASE port_record.kind
        WHEN 'ore' THEN
          UPDATE ports 
          SET ore = LEAST(native_cap, native_stock + (native_cap - native_stock) * regen_rate)
          WHERE id = port_record.id;
        WHEN 'organics' THEN
          UPDATE ports 
          SET organics = LEAST(native_cap, native_stock + (native_cap - native_stock) * regen_rate)
          WHERE id = port_record.id;
        WHEN 'goods' THEN
          UPDATE ports 
          SET goods = LEAST(native_cap, native_stock + (native_cap - native_stock) * regen_rate)
          WHERE id = port_record.id;
        WHEN 'energy' THEN
          UPDATE ports 
          SET energy = LEAST(native_cap, native_stock + (native_cap - native_stock) * regen_rate)
          WHERE id = port_record.id;
      END CASE;
    END IF;
    
    -- Decay non-native commodities (but don't go below 0)
    UPDATE ports 
    SET 
      ore = CASE WHEN port_record.kind != 'ore' THEN GREATEST(0, ore - (ore * decay_rate)) ELSE ore END,
      organics = CASE WHEN port_record.kind != 'organics' THEN GREATEST(0, organics - (organics * decay_rate)) ELSE organics END,
      goods = CASE WHEN port_record.kind != 'goods' THEN GREATEST(0, goods - (goods * decay_rate)) ELSE goods END,
      energy = CASE WHEN port_record.kind != 'energy' THEN GREATEST(0, energy - (energy * decay_rate)) ELSE energy END
    WHERE id = port_record.id;
    
    updated_count := updated_count + 1;
  END LOOP;
  
  RETURN updated_count;
END;
$$;


ALTER FUNCTION "public"."update_port_stock_dynamics"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_port_stock_dynamics"("p_universe_id" "uuid") RETURNS TABLE("ports_updated" integer, "ports_regenerated" integer, "ports_decayed" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_ports_updated integer := 0;
  v_ports_regenerated integer := 0;
  v_ports_decayed integer := 0;
  port_record RECORD;
  new_ore integer;
  new_organics integer;
  new_goods integer;
  new_energy integer;
  regen_amount integer;
  decay_amount integer;
  had_regen boolean;
  had_decay boolean;
BEGIN
  -- Process each port individually with safety checks
  FOR port_record IN 
    SELECT p.id, p.kind, p.ore, p.organics, p.goods, p.energy
    FROM public.ports p
    JOIN public.sectors s ON s.id = p.sector_id
    WHERE s.universe_id = p_universe_id
      AND p.kind IN ('ore','organics','goods','energy')
  LOOP
    -- Initialize new values
    new_ore := port_record.ore;
    new_organics := port_record.organics;
    new_goods := port_record.goods;
    new_energy := port_record.energy;
    had_regen := false;
    had_decay := false;
    
    -- Handle each commodity based on port type with safety checks
    CASE port_record.kind
      WHEN 'ore' THEN
        -- Ore port: regenerate ore toward 100M cap, decay others
        IF port_record.ore < 100000000 THEN
          regen_amount := ((100000000 - port_record.ore) * 0.1)::integer;
          new_ore := LEAST(100000000, port_record.ore + regen_amount);
          had_regen := true;
        END IF;
        
        IF port_record.organics > 0 THEN
          decay_amount := (port_record.organics * 0.05)::integer;
          new_organics := GREATEST(0, port_record.organics - decay_amount);
          had_decay := true;
        END IF;
        
        IF port_record.goods > 0 THEN
          decay_amount := (port_record.goods * 0.05)::integer;
          new_goods := GREATEST(0, port_record.goods - decay_amount);
          had_decay := true;
        END IF;
        
        IF port_record.energy > 0 THEN
          decay_amount := (port_record.energy * 0.05)::integer;
          new_energy := GREATEST(0, port_record.energy - decay_amount);
          had_decay := true;
        END IF;
        
      WHEN 'organics' THEN
        -- Organics port: regenerate organics toward 100M cap, decay others
        IF port_record.organics < 100000000 THEN
          regen_amount := ((100000000 - port_record.organics) * 0.1)::integer;
          new_organics := LEAST(100000000, port_record.organics + regen_amount);
          had_regen := true;
        END IF;
        
        IF port_record.ore > 0 THEN
          decay_amount := (port_record.ore * 0.05)::integer;
          new_ore := GREATEST(0, port_record.ore - decay_amount);
          had_decay := true;
        END IF;
        
        IF port_record.goods > 0 THEN
          decay_amount := (port_record.goods * 0.05)::integer;
          new_goods := GREATEST(0, port_record.goods - decay_amount);
          had_decay := true;
        END IF;
        
        IF port_record.energy > 0 THEN
          decay_amount := (port_record.energy * 0.05)::integer;
          new_energy := GREATEST(0, port_record.energy - decay_amount);
          had_decay := true;
        END IF;
        
      WHEN 'goods' THEN
        -- Goods port: regenerate goods toward 100M cap, decay others
        IF port_record.goods < 100000000 THEN
          regen_amount := ((100000000 - port_record.goods) * 0.1)::integer;
          new_goods := LEAST(100000000, port_record.goods + regen_amount);
          had_regen := true;
        END IF;
        
        IF port_record.ore > 0 THEN
          decay_amount := (port_record.ore * 0.05)::integer;
          new_ore := GREATEST(0, port_record.ore - decay_amount);
          had_decay := true;
        END IF;
        
        IF port_record.organics > 0 THEN
          decay_amount := (port_record.organics * 0.05)::integer;
          new_organics := GREATEST(0, port_record.organics - decay_amount);
          had_decay := true;
        END IF;
        
        IF port_record.energy > 0 THEN
          decay_amount := (port_record.energy * 0.05)::integer;
          new_energy := GREATEST(0, port_record.energy - decay_amount);
          had_decay := true;
        END IF;
        
      WHEN 'energy' THEN
        -- Energy port: regenerate energy toward 1B cap, decay others
        IF port_record.energy < 1000000000 THEN
          regen_amount := ((1000000000 - port_record.energy) * 0.1)::integer;
          new_energy := LEAST(1000000000, port_record.energy + regen_amount);
          had_regen := true;
        END IF;
        
        IF port_record.ore > 0 THEN
          decay_amount := (port_record.ore * 0.05)::integer;
          new_ore := GREATEST(0, port_record.ore - decay_amount);
          had_decay := true;
        END IF;
        
        IF port_record.organics > 0 THEN
          decay_amount := (port_record.organics * 0.05)::integer;
          new_organics := GREATEST(0, port_record.organics - decay_amount);
          had_decay := true;
        END IF;
        
        IF port_record.goods > 0 THEN
          decay_amount := (port_record.goods * 0.05)::integer;
          new_goods := GREATEST(0, port_record.goods - decay_amount);
          had_decay := true;
        END IF;
    END CASE;
    
    -- Update the port
    UPDATE public.ports 
    SET 
      ore = new_ore,
      organics = new_organics,
      goods = new_goods,
      energy = new_energy
    WHERE id = port_record.id;
    
    -- Count changes
    v_ports_updated := v_ports_updated + 1;
    IF had_regen THEN v_ports_regenerated := v_ports_regenerated + 1; END IF;
    IF had_decay THEN v_ports_decayed := v_ports_decayed + 1; END IF;
  END LOOP;

  RETURN QUERY SELECT v_ports_updated, v_ports_regenerated, v_ports_decayed;
END;
$$;


ALTER FUNCTION "public"."update_port_stock_dynamics"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_route_stats"("p_route_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_total_profit BIGINT := 0;
    v_total_turns INTEGER := 0;
    v_iterations INTEGER := 0;
BEGIN
    -- Calculate total profit and turns from executions
    SELECT 
        COALESCE(SUM(total_profit), 0),
        COALESCE(SUM(turns_spent), 0),
        COUNT(*)
    INTO v_total_profit, v_total_turns, v_iterations
    FROM route_executions 
    WHERE route_id = p_route_id AND status = 'completed';
    
    -- Update route statistics
    UPDATE trade_routes 
    SET 
        total_profit = v_total_profit,
        total_turns_spent = v_total_turns,
        current_iteration = v_iterations,
        updated_at = now()
    WHERE id = p_route_id;
END;
$$;


ALTER FUNCTION "public"."update_route_stats"("p_route_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_scheduler_timestamp"("p_universe_id" "uuid", "p_event_type" "text", "p_timestamp" timestamp with time zone DEFAULT "now"()) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    CASE p_event_type
        WHEN 'turn_generation' THEN
            UPDATE public.universe_settings 
            SET last_turn_generation = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'port_regeneration' THEN
            UPDATE public.universe_settings 
            SET last_port_regeneration_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'rankings' THEN
            UPDATE public.universe_settings 
            SET last_rankings_generation_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'defenses_check' THEN
            UPDATE public.universe_settings 
            SET last_defenses_check_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'xenobes_play' THEN
            UPDATE public.universe_settings 
            SET last_xenobes_play_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'igb_interest' THEN
            UPDATE public.universe_settings 
            SET last_igb_interest_accumulation_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'news' THEN
            UPDATE public.universe_settings 
            SET last_news_generation_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'planet_production' THEN
            UPDATE public.universe_settings 
            SET last_planet_production_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'ships_tow_fed' THEN
            UPDATE public.universe_settings 
            SET last_ships_tow_from_fed_sectors_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'sector_defenses_degrade' THEN
            UPDATE public.universe_settings 
            SET last_sector_defenses_degrade_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'apocalypse' THEN
            UPDATE public.universe_settings 
            SET last_planetary_apocalypse_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'heartbeat' THEN
            -- Heartbeat doesn't need a timestamp update, just return true
            RETURN true;
        ELSE
            -- Log unknown event type but don't fail
            RAISE WARNING 'Unknown event type: %', p_event_type;
            RETURN false;
    END CASE;
    
    RETURN true;
END;
$$;


ALTER FUNCTION "public"."update_scheduler_timestamp"("p_universe_id" "uuid", "p_event_type" "text", "p_timestamp" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_sector_ownership"("p_sector_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_sector RECORD;
  v_player_bases RECORD;
  v_new_owner UUID;
BEGIN
  -- Get current sector info
  SELECT id, number, universe_id, owner_player_id, name
  INTO v_sector
  FROM public.sectors
  WHERE id = p_sector_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Federation sectors (0-10) cannot change ownership
  IF v_sector.number BETWEEN 0 AND 10 THEN
    RETURN;
  END IF;

  -- Count bases per player in this sector
  SELECT 
    owner_player_id,
    COUNT(*) as base_count
  INTO v_player_bases
  FROM public.planets
  WHERE sector_id = p_sector_id
    AND owner_player_id IS NOT NULL
    AND base_built = true
  GROUP BY owner_player_id
  HAVING COUNT(*) >= 3
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- If a player has 3+ bases, they own the sector
  IF FOUND THEN
    v_new_owner := v_player_bases.owner_player_id;
  ELSE
    v_new_owner := NULL;
  END IF;

  -- Update ownership if changed
  IF v_new_owner IS DISTINCT FROM v_sector.owner_player_id THEN
    UPDATE public.sectors
    SET 
      owner_player_id = v_new_owner,
      controlled = (v_new_owner IS NOT NULL),
      name = CASE
        WHEN v_new_owner IS NULL THEN 'Uncharted Territory'
        WHEN v_new_owner IS NOT NULL AND (v_sector.name IS NULL OR v_sector.name = 'Uncharted Territory') THEN 'Uncharted Territory'
        ELSE v_sector.name
      END
    WHERE id = p_sector_id;

    IF v_new_owner IS NOT NULL THEN
      RAISE NOTICE 'Sector % is now owned by player %', v_sector.number, v_new_owner;
    ELSE
      RAISE NOTICE 'Sector % is now unowned', v_sector.number;
    END IF;
  END IF;
END;
$$;


ALTER FUNCTION "public"."update_sector_ownership"("p_sector_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_sector_ownership"("p_sector_id" "uuid") IS 'Updates sector ownership based on player having 3+ bases in the sector';



CREATE OR REPLACE FUNCTION "public"."update_sector_rules"("p_sector_id" "uuid", "p_player_id" "uuid", "p_allow_attacking" boolean DEFAULT NULL::boolean, "p_allow_trading" "text" DEFAULT NULL::"text", "p_allow_planet_creation" "text" DEFAULT NULL::"text", "p_allow_sector_defense" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_sector RECORD;
BEGIN
  -- Get sector info
  SELECT id, number, owner_player_id
  INTO v_sector
  FROM public.sectors
  WHERE id = p_sector_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'sector_not_found');
  END IF;

  -- Federation sectors cannot have rules changed
  IF v_sector.number BETWEEN 0 AND 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'federation_sector', 'message', 'Federation sector rules cannot be modified');
  END IF;

  -- Only the owner can update rules
  IF v_sector.owner_player_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'sector_not_owned', 'message', 'You must own this sector to set rules');
  END IF;

  IF v_sector.owner_player_id != p_player_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_owner', 'message', 'Only the sector owner can set rules');
  END IF;

  -- Update rules (only update fields that are provided)
  UPDATE public.sectors
  SET 
    allow_attacking = COALESCE(p_allow_attacking, allow_attacking),
    allow_trading = COALESCE(p_allow_trading, allow_trading),
    allow_planet_creation = COALESCE(p_allow_planet_creation, allow_planet_creation),
    allow_sector_defense = COALESCE(p_allow_sector_defense, allow_sector_defense)
  WHERE id = p_sector_id;

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."update_sector_rules"("p_sector_id" "uuid", "p_player_id" "uuid", "p_allow_attacking" boolean, "p_allow_trading" "text", "p_allow_planet_creation" "text", "p_allow_sector_defense" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_sector_rules"("p_sector_id" "uuid", "p_player_id" "uuid", "p_allow_attacking" boolean, "p_allow_trading" "text", "p_allow_planet_creation" "text", "p_allow_sector_defense" "text") IS 'Allows sector owner to update sector rules';



CREATE OR REPLACE FUNCTION "public"."update_universe_economy"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- TODO: Implement universe economy updates
    -- This should handle economic calculations, trade route updates, etc.
    
    RETURN jsonb_build_object(
        'message', 'Universe economy update placeholder - not yet implemented',
        'universe_id', p_universe_id,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."update_universe_economy"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_universe_rankings"("p_universe_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_updated_count INTEGER := 0;
BEGIN
  -- Refresh all player scores in the universe
  UPDATE public.players
  SET score = calculate_player_score(id)
  WHERE universe_id = p_universe_id;
  
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Rankings updated',
    'players_updated', v_updated_count
  );
END;
$$;


ALTER FUNCTION "public"."update_universe_rankings"("p_universe_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_universe_settings"("p_universe_id" "uuid", "p_settings" "jsonb", "p_updated_by" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE universe_settings SET
    game_version = COALESCE((p_settings->>'game_version')::TEXT, game_version),
    game_name = COALESCE((p_settings->>'game_name')::TEXT, game_name),
    avg_tech_level_mines = COALESCE((p_settings->>'avg_tech_level_mines')::INTEGER, avg_tech_level_mines),
    avg_tech_emergency_warp_degrade = COALESCE((p_settings->>'avg_tech_emergency_warp_degrade')::INTEGER, avg_tech_emergency_warp_degrade),
    max_avg_tech_federation_sectors = COALESCE((p_settings->>'max_avg_tech_federation_sectors')::INTEGER, max_avg_tech_federation_sectors),
    tech_level_upgrade_bases = COALESCE((p_settings->>'tech_level_upgrade_bases')::INTEGER, tech_level_upgrade_bases),
    number_of_sectors = COALESCE((p_settings->>'number_of_sectors')::INTEGER, number_of_sectors),
    max_links_per_sector = COALESCE((p_settings->>'max_links_per_sector')::INTEGER, max_links_per_sector),
    max_planets_per_sector = COALESCE((p_settings->>'max_planets_per_sector')::INTEGER, max_planets_per_sector),
    planets_needed_for_sector_ownership = COALESCE((p_settings->>'planets_needed_for_sector_ownership')::INTEGER, planets_needed_for_sector_ownership),
    igb_enabled = COALESCE((p_settings->>'igb_enabled')::BOOLEAN, igb_enabled),
    igb_interest_rate_per_update = COALESCE((p_settings->>'igb_interest_rate_per_update')::NUMERIC, igb_interest_rate_per_update),
    igb_loan_rate_per_update = COALESCE((p_settings->>'igb_loan_rate_per_update')::NUMERIC, igb_loan_rate_per_update),
    planet_interest_rate = COALESCE((p_settings->>'planet_interest_rate')::NUMERIC, planet_interest_rate),
    colonists_limit = COALESCE((p_settings->>'colonists_limit')::BIGINT, colonists_limit),
    colonist_production_rate = COALESCE((p_settings->>'colonist_production_rate')::NUMERIC, colonist_production_rate),
    colonists_per_fighter = COALESCE((p_settings->>'colonists_per_fighter')::INTEGER, colonists_per_fighter),
    colonists_per_torpedo = COALESCE((p_settings->>'colonists_per_torpedo')::INTEGER, colonists_per_torpedo),
    colonists_per_ore = COALESCE((p_settings->>'colonists_per_ore')::INTEGER, colonists_per_ore),
    colonists_per_organics = COALESCE((p_settings->>'colonists_per_organics')::INTEGER, colonists_per_organics),
    colonists_per_goods = COALESCE((p_settings->>'colonists_per_goods')::INTEGER, colonists_per_goods),
    colonists_per_energy = COALESCE((p_settings->>'colonists_per_energy')::INTEGER, colonists_per_energy),
    colonists_per_credits = COALESCE((p_settings->>'colonists_per_credits')::INTEGER, colonists_per_credits),
    max_accumulated_turns = COALESCE((p_settings->>'max_accumulated_turns')::INTEGER, max_accumulated_turns),
    max_traderoutes_per_player = COALESCE((p_settings->>'max_traderoutes_per_player')::INTEGER, max_traderoutes_per_player),
    energy_per_sector_fighter = COALESCE((p_settings->>'energy_per_sector_fighter')::NUMERIC, energy_per_sector_fighter),
    sector_fighter_degradation_rate = COALESCE((p_settings->>'sector_fighter_degradation_rate')::NUMERIC, sector_fighter_degradation_rate),
    tick_interval_minutes = COALESCE((p_settings->>'tick_interval_minutes')::INTEGER, tick_interval_minutes),
    turns_generation_interval_minutes = COALESCE((p_settings->>'turns_generation_interval_minutes')::INTEGER, turns_generation_interval_minutes),
    turns_per_generation = COALESCE((p_settings->>'turns_per_generation')::INTEGER, turns_per_generation),
    defenses_check_interval_minutes = COALESCE((p_settings->>'defenses_check_interval_minutes')::INTEGER, defenses_check_interval_minutes),
    xenobes_play_interval_minutes = COALESCE((p_settings->>'xenobes_play_interval_minutes')::INTEGER, xenobes_play_interval_minutes),
    igb_interest_accumulation_interval_minutes = COALESCE((p_settings->>'igb_interest_accumulation_interval_minutes')::INTEGER, igb_interest_accumulation_interval_minutes),
    news_generation_interval_minutes = COALESCE((p_settings->>'news_generation_interval_minutes')::INTEGER, news_generation_interval_minutes),
    planet_production_interval_minutes = COALESCE((p_settings->>'planet_production_interval_minutes')::INTEGER, planet_production_interval_minutes),
    port_regeneration_interval_minutes = COALESCE((p_settings->>'port_regeneration_interval_minutes')::INTEGER, port_regeneration_interval_minutes),
    ships_tow_from_fed_sectors_interval_minutes = COALESCE((p_settings->>'ships_tow_from_fed_sectors_interval_minutes')::INTEGER, ships_tow_from_fed_sectors_interval_minutes),
    rankings_generation_interval_minutes = COALESCE((p_settings->>'rankings_generation_interval_minutes')::INTEGER, rankings_generation_interval_minutes),
    sector_defenses_degrade_interval_minutes = COALESCE((p_settings->>'sector_defenses_degrade_interval_minutes')::INTEGER, sector_defenses_degrade_interval_minutes),
    planetary_apocalypse_interval_minutes = COALESCE((p_settings->>'planetary_apocalypse_interval_minutes')::INTEGER, planetary_apocalypse_interval_minutes),
    use_new_planet_update_code = COALESCE((p_settings->>'use_new_planet_update_code')::BOOLEAN, use_new_planet_update_code),
    limit_captured_planets_max_credits = COALESCE((p_settings->>'limit_captured_planets_max_credits')::BOOLEAN, limit_captured_planets_max_credits),
    captured_planets_max_credits = COALESCE((p_settings->>'captured_planets_max_credits')::BIGINT, captured_planets_max_credits),
    updated_by = p_updated_by,
    updated_at = NOW()
  WHERE universe_id = p_universe_id;
  
  RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."update_universe_settings"("p_universe_id" "uuid", "p_settings" "jsonb", "p_updated_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."user_owns_planet"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_owns_planet BOOLEAN := FALSE;
BEGIN
  -- Check if any of the user's players in this universe own the planet
  SELECT EXISTS(
    SELECT 1 
    FROM planets p
    JOIN players pl ON p.owner_player_id = pl.id
    WHERE p.id = p_planet_id 
    AND pl.user_id = p_user_id 
    AND pl.universe_id = p_universe_id
  ) INTO v_owns_planet;
  
  RETURN v_owns_planet;
END;
$$;


ALTER FUNCTION "public"."user_owns_planet"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_route_waypoints"("p_route_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_waypoint_count INTEGER;
    v_sequence_gaps BOOLEAN;
BEGIN
    -- Check if route has waypoints
    SELECT COUNT(*) INTO v_waypoint_count
    FROM route_waypoints 
    WHERE route_id = p_route_id;
    
    IF v_waypoint_count = 0 THEN
        RETURN false;
    END IF;
    
    -- Check for sequence gaps
    SELECT EXISTS(
        SELECT 1 FROM (
            SELECT sequence_order, 
                   LAG(sequence_order) OVER (ORDER BY sequence_order) as prev_order
            FROM route_waypoints 
            WHERE route_id = p_route_id
        ) gaps
        WHERE sequence_order - COALESCE(prev_order, 0) > 1
    ) INTO v_sequence_gaps;
    
    RETURN NOT v_sequence_gaps;
END;
$$;


ALTER FUNCTION "public"."validate_route_waypoints"("p_route_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."ai_action_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "universe_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "target_sector_id" "uuid",
    "target_planet_id" "uuid",
    "credits_before" bigint,
    "credits_after" bigint,
    "turns_before" integer,
    "turns_after" integer,
    "outcome" "text" NOT NULL,
    "message" "text"
);


ALTER TABLE "public"."ai_action_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_names" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "name_type" "text" NOT NULL,
    CONSTRAINT "ai_names_name_type_check" CHECK (("name_type" = ANY (ARRAY['first'::"text", 'last'::"text", 'title'::"text"])))
);


ALTER TABLE "public"."ai_names" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."ai_names_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."ai_names_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."ai_names_id_seq" OWNED BY "public"."ai_names"."id";



CREATE TABLE IF NOT EXISTS "public"."ai_player_memory" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "player_id" "uuid" NOT NULL,
    "last_action" timestamp without time zone DEFAULT "now"(),
    "current_goal" "text",
    "target_sector_id" "uuid",
    "trade_route" "jsonb",
    "exploration_targets" "jsonb" DEFAULT '[]'::"jsonb",
    "owned_planets" integer DEFAULT 0,
    "last_profit" bigint DEFAULT 0,
    "consecutive_losses" integer DEFAULT 0,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."ai_player_memory" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_players" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "universe_id" "uuid",
    "name" "text" NOT NULL,
    "ai_type" "text" DEFAULT 'balanced'::"text",
    "economic_score" integer DEFAULT 0,
    "territorial_score" integer DEFAULT 0,
    "military_score" integer DEFAULT 0,
    "exploration_score" integer DEFAULT 0,
    "total_score" integer DEFAULT 0,
    "rank_position" integer,
    "last_updated" timestamp without time zone DEFAULT "now"(),
    "created_at" timestamp without time zone DEFAULT "now"(),
    CONSTRAINT "ai_players_ai_type_check" CHECK (("ai_type" = ANY (ARRAY['trader'::"text", 'explorer'::"text", 'military'::"text", 'balanced'::"text"])))
);


ALTER TABLE "public"."ai_players" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_ranking_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "ai_player_id" "uuid",
    "universe_id" "uuid",
    "rank_position" integer,
    "total_score" integer,
    "economic_score" integer,
    "territorial_score" integer,
    "military_score" integer,
    "exploration_score" integer,
    "recorded_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."ai_ranking_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bnt_capacity_lookup" (
    "tech_level" integer NOT NULL,
    "capacity" bigint NOT NULL
);


ALTER TABLE "public"."bnt_capacity_lookup" OWNER TO "postgres";


COMMENT ON TABLE "public"."bnt_capacity_lookup" IS 'Lookup table for BNT capacity values (tech_level -> capacity)';



CREATE TABLE IF NOT EXISTS "public"."combats" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attacker_id" "uuid" NOT NULL,
    "defender_id" "uuid" NOT NULL,
    "outcome" "text",
    "snapshot" "jsonb",
    "at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."combats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cron_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "universe_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "event_name" "text" NOT NULL,
    "status" "text" NOT NULL,
    "message" "text",
    "execution_time_ms" integer,
    "triggered_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb" DEFAULT '{}'::"jsonb"
);


ALTER TABLE "public"."cron_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."favorites" (
    "player_id" "uuid" NOT NULL,
    "sector_id" "uuid" NOT NULL
);


ALTER TABLE "public"."favorites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."planets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sector_id" "uuid",
    "owner_player_id" "uuid",
    "name" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "colonists" bigint DEFAULT 0,
    "colonists_max" bigint DEFAULT 100000000,
    "ore" bigint DEFAULT 0,
    "organics" bigint DEFAULT 0,
    "goods" bigint DEFAULT 0,
    "energy" bigint DEFAULT 0,
    "fighters" integer DEFAULT 0,
    "torpedoes" integer DEFAULT 0,
    "shields" integer DEFAULT 0,
    "last_production" timestamp with time zone DEFAULT "now"(),
    "last_colonist_growth" timestamp with time zone DEFAULT "now"(),
    "production_ore_percent" integer DEFAULT 0,
    "production_organics_percent" integer DEFAULT 0,
    "production_goods_percent" integer DEFAULT 0,
    "production_energy_percent" integer DEFAULT 0,
    "production_fighters_percent" integer DEFAULT 0,
    "production_torpedoes_percent" integer DEFAULT 0,
    "credits" bigint DEFAULT 0,
    "base_built" boolean DEFAULT false,
    "base_cost" bigint DEFAULT 50000,
    "base_colonists_required" bigint DEFAULT 10000,
    "base_resources_required" bigint DEFAULT 10000,
    CONSTRAINT "planets_colonists_check" CHECK (("colonists" >= 0)),
    CONSTRAINT "planets_colonists_max_check" CHECK (("colonists_max" > 0)),
    CONSTRAINT "planets_credits_check" CHECK (("credits" >= 0)),
    CONSTRAINT "planets_energy_check" CHECK (("energy" >= 0)),
    CONSTRAINT "planets_fighters_check" CHECK (("fighters" >= 0)),
    CONSTRAINT "planets_goods_check" CHECK (("goods" >= 0)),
    CONSTRAINT "planets_ore_check" CHECK (("ore" >= 0)),
    CONSTRAINT "planets_organics_check" CHECK (("organics" >= 0)),
    CONSTRAINT "planets_production_allocation_check" CHECK ((((((("production_ore_percent" + "production_organics_percent") + "production_goods_percent") + "production_energy_percent") + "production_fighters_percent") + "production_torpedoes_percent") <= 100)),
    CONSTRAINT "planets_production_energy_percent_check" CHECK ((("production_energy_percent" >= 0) AND ("production_energy_percent" <= 100))),
    CONSTRAINT "planets_production_fighters_percent_check" CHECK ((("production_fighters_percent" >= 0) AND ("production_fighters_percent" <= 100))),
    CONSTRAINT "planets_production_goods_percent_check" CHECK ((("production_goods_percent" >= 0) AND ("production_goods_percent" <= 100))),
    CONSTRAINT "planets_production_ore_percent_check" CHECK ((("production_ore_percent" >= 0) AND ("production_ore_percent" <= 100))),
    CONSTRAINT "planets_production_organics_percent_check" CHECK ((("production_organics_percent" >= 0) AND ("production_organics_percent" <= 100))),
    CONSTRAINT "planets_production_torpedoes_percent_check" CHECK ((("production_torpedoes_percent" >= 0) AND ("production_torpedoes_percent" <= 100))),
    CONSTRAINT "planets_shields_check" CHECK (("shields" >= 0)),
    CONSTRAINT "planets_torpedoes_check" CHECK (("torpedoes" >= 0))
);


ALTER TABLE "public"."planets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."player_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "player_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "ref_id" "uuid",
    "message" "text" NOT NULL,
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."player_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."player_rankings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "player_id" "uuid",
    "universe_id" "uuid",
    "economic_score" integer DEFAULT 0,
    "territorial_score" integer DEFAULT 0,
    "military_score" integer DEFAULT 0,
    "exploration_score" integer DEFAULT 0,
    "total_score" integer DEFAULT 0,
    "rank_position" integer,
    "last_updated" timestamp without time zone DEFAULT "now"(),
    "created_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."player_rankings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."players" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "universe_id" "uuid" NOT NULL,
    "handle" "text" NOT NULL,
    "turns" integer DEFAULT 60,
    "current_sector" "uuid",
    "last_turn_ts" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_ai" boolean DEFAULT false,
    "turns_spent" bigint DEFAULT 0,
    "last_login" timestamp with time zone,
    "ai_personality" "public"."ai_personality" DEFAULT 'balanced'::"public"."ai_personality",
    "score" bigint DEFAULT 0,
    CONSTRAINT "players_turns_spent_check" CHECK (("turns_spent" >= 0))
);


ALTER TABLE "public"."players" OWNER TO "postgres";


COMMENT ON COLUMN "public"."players"."last_login" IS 'Timestamp of when the player was last active, used for online status determination';



CREATE TABLE IF NOT EXISTS "public"."ports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sector_id" "uuid" NOT NULL,
    "kind" "text" DEFAULT 'trade'::"text",
    "ore" integer DEFAULT 0,
    "organics" integer DEFAULT 0,
    "goods" integer DEFAULT 0,
    "energy" integer DEFAULT 0,
    "price_ore" numeric DEFAULT 10.0,
    "price_organics" numeric DEFAULT 15.0,
    "price_goods" numeric DEFAULT 25.0,
    "price_energy" numeric DEFAULT 5.0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "stock_enforced" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ranking_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "player_id" "uuid",
    "universe_id" "uuid",
    "rank_position" integer,
    "total_score" integer,
    "economic_score" integer,
    "territorial_score" integer,
    "military_score" integer,
    "exploration_score" integer,
    "recorded_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."ranking_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."route_executions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "route_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"(),
    "completed_at" timestamp with time zone,
    "status" "text" DEFAULT 'running'::"text",
    "current_waypoint" integer DEFAULT 1,
    "total_profit" bigint DEFAULT 0,
    "turns_spent" integer DEFAULT 0,
    "error_message" "text",
    "execution_data" "jsonb" DEFAULT '{}'::"jsonb",
    CONSTRAINT "route_executions_status_check" CHECK (("status" = ANY (ARRAY['running'::"text", 'completed'::"text", 'failed'::"text", 'paused'::"text"])))
);


ALTER TABLE "public"."route_executions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."route_profitability" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "route_id" "uuid" NOT NULL,
    "calculated_at" timestamp with time zone DEFAULT "now"(),
    "estimated_profit_per_cycle" bigint,
    "estimated_turns_per_cycle" integer,
    "profit_per_turn" numeric,
    "cargo_efficiency" numeric,
    "market_conditions" "jsonb" DEFAULT '{}'::"jsonb",
    "is_current" boolean DEFAULT true
);


ALTER TABLE "public"."route_profitability" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."route_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "template_data" "jsonb" NOT NULL,
    "difficulty_level" integer DEFAULT 1,
    "required_engine_level" integer DEFAULT 1,
    "required_cargo_capacity" integer DEFAULT 1000,
    "estimated_profit_per_turn" numeric,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "route_templates_difficulty_level_check" CHECK ((("difficulty_level" >= 1) AND ("difficulty_level" <= 5)))
);


ALTER TABLE "public"."route_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."route_waypoints" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "route_id" "uuid" NOT NULL,
    "sequence_order" integer NOT NULL,
    "port_id" "uuid" NOT NULL,
    "action_type" "text" NOT NULL,
    "resource" "text",
    "quantity" integer DEFAULT 0,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "route_waypoints_action_type_check" CHECK (("action_type" = ANY (ARRAY['buy'::"text", 'sell'::"text", 'trade_auto'::"text"]))),
    CONSTRAINT "route_waypoints_resource_check" CHECK (("resource" = ANY (ARRAY['ore'::"text", 'organics'::"text", 'goods'::"text", 'energy'::"text"])))
);


ALTER TABLE "public"."route_waypoints" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."scans" (
    "player_id" "uuid" NOT NULL,
    "sector_id" "uuid" NOT NULL,
    "mode" "text",
    "scanned_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "scans_mode_check" CHECK (("mode" = ANY (ARRAY['single'::"text", 'full'::"text"])))
);


ALTER TABLE "public"."scans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sectors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "universe_id" "uuid" NOT NULL,
    "number" integer NOT NULL,
    "meta" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "owner_player_id" "uuid",
    "controlled" boolean DEFAULT false,
    "ownership_threshold" integer DEFAULT 3,
    "name" "text",
    "last_visited_at" timestamp with time zone,
    "last_visited_by" "uuid",
    "last_player_visited" "uuid",
    "allow_attacking" boolean DEFAULT true,
    "allow_trading" "text" DEFAULT 'yes'::"text",
    "allow_planet_creation" "text" DEFAULT 'yes'::"text",
    "allow_sector_defense" "text" DEFAULT 'yes'::"text",
    CONSTRAINT "sectors_allow_planet_creation_check" CHECK (("allow_planet_creation" = ANY (ARRAY['yes'::"text", 'no'::"text", 'allies_only'::"text"]))),
    CONSTRAINT "sectors_allow_sector_defense_check" CHECK (("allow_sector_defense" = ANY (ARRAY['yes'::"text", 'no'::"text", 'allies_only'::"text"]))),
    CONSTRAINT "sectors_allow_trading_check" CHECK (("allow_trading" = ANY (ARRAY['yes'::"text", 'no'::"text", 'allies_only'::"text"])))
);


ALTER TABLE "public"."sectors" OWNER TO "postgres";


COMMENT ON COLUMN "public"."sectors"."allow_attacking" IS 'Whether combat is allowed in this sector';



COMMENT ON COLUMN "public"."sectors"."allow_trading" IS 'Trading restrictions: yes, no, or allies_only';



COMMENT ON COLUMN "public"."sectors"."allow_planet_creation" IS 'Planet creation restrictions: yes, no, or allies_only';



COMMENT ON COLUMN "public"."sectors"."allow_sector_defense" IS 'Mine deployment restrictions: yes, no, or allies_only';



CREATE TABLE IF NOT EXISTS "public"."ships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "player_id" "uuid" NOT NULL,
    "name" "text" DEFAULT 'Scout'::"text",
    "hull" integer DEFAULT 100,
    "shield" integer DEFAULT 0,
    "fighters" integer DEFAULT 0,
    "torpedoes" integer DEFAULT 0,
    "engine_lvl" integer DEFAULT 1,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "shield_lvl" integer DEFAULT 0,
    "comp_lvl" integer DEFAULT 1,
    "sensor_lvl" integer DEFAULT 1,
    "hull_lvl" integer DEFAULT 1,
    "cargo" integer DEFAULT 1000,
    "armor" integer DEFAULT 0,
    "device_space_beacons" integer DEFAULT 0,
    "device_warp_editors" integer DEFAULT 0,
    "device_genesis_torpedoes" integer DEFAULT 0,
    "device_mine_deflectors" integer DEFAULT 0,
    "device_emergency_warp" boolean DEFAULT false,
    "device_escape_pod" boolean DEFAULT true,
    "device_fuel_scoop" boolean DEFAULT false,
    "device_last_seen" boolean DEFAULT false,
    "power_lvl" integer DEFAULT 1,
    "beam_lvl" integer DEFAULT 0,
    "torp_launcher_lvl" integer DEFAULT 0,
    "cloak_lvl" integer DEFAULT 0,
    "colonists" integer DEFAULT 0,
    "energy" integer DEFAULT 0,
    "ore" integer DEFAULT 0,
    "organics" integer DEFAULT 0,
    "goods" integer DEFAULT 0,
    "credits" bigint DEFAULT 0,
    "armor_lvl" integer DEFAULT 1,
    "hull_max" integer GENERATED ALWAYS AS (((100)::numeric * "power"(1.5, (("hull_lvl" - 1))::numeric))) STORED,
    "armor_max" integer GENERATED ALWAYS AS (((100)::numeric * "power"(1.5, (("armor_lvl" - 1))::numeric))) STORED,
    "energy_max" integer GENERATED ALWAYS AS (((100)::numeric * "power"(1.5, (("power_lvl" - 1))::numeric))) STORED,
    CONSTRAINT "ships_armor_range" CHECK ((("armor" >= 0) AND ("armor" <= "armor_max"))),
    CONSTRAINT "ships_beam_lvl_range" CHECK (("beam_lvl" >= 0)),
    CONSTRAINT "ships_cloak_lvl_range" CHECK (("cloak_lvl" >= 0)),
    CONSTRAINT "ships_colonists_range" CHECK (("colonists" >= 0)),
    CONSTRAINT "ships_credits_check" CHECK (("credits" >= 0)),
    CONSTRAINT "ships_device_genesis_torpedoes_range" CHECK (("device_genesis_torpedoes" >= 0)),
    CONSTRAINT "ships_device_mine_deflectors_range" CHECK (("device_mine_deflectors" >= 0)),
    CONSTRAINT "ships_device_space_beacons_range" CHECK (("device_space_beacons" >= 0)),
    CONSTRAINT "ships_device_warp_editors_range" CHECK (("device_warp_editors" >= 0)),
    CONSTRAINT "ships_energy_range" CHECK ((("energy" >= 0) AND ("energy" <= "energy_max"))),
    CONSTRAINT "ships_fighters_range" CHECK (("fighters" >= 0)),
    CONSTRAINT "ships_goods_range" CHECK (("goods" >= 0)),
    CONSTRAINT "ships_hull_range" CHECK ((("hull" >= 0) AND ("hull" <= "hull_max"))),
    CONSTRAINT "ships_ore_range" CHECK (("ore" >= 0)),
    CONSTRAINT "ships_organics_range" CHECK (("organics" >= 0)),
    CONSTRAINT "ships_power_lvl_range" CHECK (("power_lvl" >= 0)),
    CONSTRAINT "ships_torp_launcher_lvl_range" CHECK (("torp_launcher_lvl" >= 0)),
    CONSTRAINT "ships_torpedoes_range" CHECK (("torpedoes" >= 0))
);


ALTER TABLE "public"."ships" OWNER TO "postgres";


COMMENT ON TABLE "public"."ships" IS 'Ships table now includes inventory data (colonists, ore, organics, goods, energy)';



CREATE TABLE IF NOT EXISTS "public"."trade_routes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "player_id" "uuid" NOT NULL,
    "universe_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT false,
    "is_automated" boolean DEFAULT false,
    "max_iterations" integer DEFAULT 0,
    "current_iteration" integer DEFAULT 0,
    "total_profit" bigint DEFAULT 0,
    "total_turns_spent" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_executed_at" timestamp with time zone,
    "movement_type" "text" DEFAULT 'warp'::"text",
    CONSTRAINT "trade_routes_movement_type_check" CHECK (("movement_type" = ANY (ARRAY['warp'::"text", 'realspace'::"text"])))
);


ALTER TABLE "public"."trade_routes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."trades" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "player_id" "uuid" NOT NULL,
    "port_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "resource" "text" NOT NULL,
    "qty" integer NOT NULL,
    "price" numeric NOT NULL,
    "at" timestamp with time zone DEFAULT "now"(),
    "quantity" bigint,
    "unit_price" numeric,
    "total_price" numeric,
    CONSTRAINT "trades_action_check" CHECK (("action" = ANY (ARRAY['buy'::"text", 'sell'::"text"]))),
    CONSTRAINT "trades_resource_check" CHECK (("resource" = ANY (ARRAY['ore'::"text", 'organics'::"text", 'goods'::"text", 'energy'::"text", 'fighters'::"text", 'torpedoes'::"text", 'hull_repair'::"text"])))
);


ALTER TABLE "public"."trades" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."universe_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "universe_id" "uuid" NOT NULL,
    "game_version" "text" DEFAULT '0.663'::"text",
    "game_name" "text" DEFAULT 'BNT Redux'::"text",
    "avg_tech_emergency_warp_degrade" integer DEFAULT 15,
    "max_avg_tech_federation_sectors" integer DEFAULT 8,
    "tech_level_upgrade_bases" integer DEFAULT 1,
    "number_of_sectors" integer DEFAULT 1000,
    "max_links_per_sector" integer DEFAULT 10,
    "max_planets_per_sector" integer DEFAULT 10,
    "planets_needed_for_sector_ownership" integer DEFAULT 5,
    "igb_enabled" boolean DEFAULT true,
    "igb_interest_rate_per_update" numeric(10,6) DEFAULT 0.05,
    "igb_loan_rate_per_update" numeric(10,6) DEFAULT 0.1,
    "planet_interest_rate" numeric(10,6) DEFAULT 0.06,
    "colonists_limit" bigint DEFAULT '100000000000'::bigint,
    "colonist_production_rate" numeric(10,6) DEFAULT 0.005,
    "colonists_per_fighter" integer DEFAULT 20000,
    "colonists_per_torpedo" integer DEFAULT 8000,
    "colonists_per_ore" integer DEFAULT 800,
    "colonists_per_organics" integer DEFAULT 400,
    "colonists_per_goods" integer DEFAULT 800,
    "colonists_per_energy" integer DEFAULT 400,
    "colonists_per_credits" integer DEFAULT 67,
    "max_accumulated_turns" integer DEFAULT 5000,
    "max_traderoutes_per_player" integer DEFAULT 40,
    "energy_per_sector_fighter" numeric(10,3) DEFAULT 0.1,
    "sector_fighter_degradation_rate" numeric(10,3) DEFAULT 5.0,
    "tick_interval_minutes" integer DEFAULT 6,
    "turns_generation_interval_minutes" integer DEFAULT 3,
    "turns_per_generation" integer DEFAULT 12,
    "defenses_check_interval_minutes" integer DEFAULT 3,
    "xenobes_play_interval_minutes" integer DEFAULT 3,
    "igb_interest_accumulation_interval_minutes" integer DEFAULT 2,
    "news_generation_interval_minutes" integer DEFAULT 6,
    "planet_production_interval_minutes" integer DEFAULT 2,
    "port_regeneration_interval_minutes" integer DEFAULT 1,
    "ships_tow_from_fed_sectors_interval_minutes" integer DEFAULT 3,
    "rankings_generation_interval_minutes" integer DEFAULT 1,
    "sector_defenses_degrade_interval_minutes" integer DEFAULT 6,
    "planetary_apocalypse_interval_minutes" integer DEFAULT 60,
    "use_new_planet_update_code" boolean DEFAULT true,
    "limit_captured_planets_max_credits" boolean DEFAULT false,
    "captured_planets_max_credits" bigint DEFAULT 1000000000,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_by" "uuid",
    "turn_generation_interval_minutes" integer DEFAULT 3,
    "cycle_interval_minutes" integer DEFAULT 6,
    "update_interval_minutes" integer DEFAULT 1,
    "last_turn_generation" timestamp with time zone,
    "last_cycle_event" timestamp with time zone,
    "last_update_event" timestamp with time zone,
    "avg_tech_level_emergency_warp_degrades" integer DEFAULT 15,
    "last_port_regeneration_event" timestamp with time zone,
    "last_rankings_generation_event" timestamp with time zone,
    "last_defenses_check_event" timestamp with time zone,
    "last_xenobes_play_event" timestamp with time zone,
    "last_igb_interest_accumulation_event" timestamp with time zone,
    "last_news_generation_event" timestamp with time zone,
    "last_planet_production_event" timestamp with time zone,
    "last_ships_tow_from_fed_sectors_event" timestamp with time zone,
    "last_sector_defenses_degrade_event" timestamp with time zone,
    "last_planetary_apocalypse_event" timestamp with time zone,
    "planet_base_cost" bigint DEFAULT 50000,
    "planet_base_colonists_required" bigint DEFAULT 10000,
    "planet_base_resources_required" bigint DEFAULT 10000,
    "sector_ownership_threshold" integer DEFAULT 3,
    "ai_player_count" integer DEFAULT 5,
    "ai_aggression_level" integer DEFAULT 3,
    "ai_trade_frequency" integer DEFAULT 2,
    "ai_player_actions_interval_minutes" integer DEFAULT 5,
    "last_ai_player_actions_event" timestamp with time zone,
    "avg_tech_level_mines" integer DEFAULT 5,
    "ai_actions_enabled" boolean DEFAULT false,
    CONSTRAINT "universe_settings_ai_aggression_level_check" CHECK ((("ai_aggression_level" >= 1) AND ("ai_aggression_level" <= 5))),
    CONSTRAINT "universe_settings_ai_trade_frequency_check" CHECK ((("ai_trade_frequency" >= 1) AND ("ai_trade_frequency" <= 10))),
    CONSTRAINT "universe_settings_cycle_interval_positive" CHECK (("cycle_interval_minutes" > 0)),
    CONSTRAINT "universe_settings_positive_intervals" CHECK ((("tick_interval_minutes" > 0) AND ("turns_generation_interval_minutes" > 0) AND ("turns_per_generation" > 0))),
    CONSTRAINT "universe_settings_positive_limits" CHECK ((("colonists_limit" > 0) AND ("max_accumulated_turns" > 0) AND ("max_traderoutes_per_player" > 0))),
    CONSTRAINT "universe_settings_positive_links" CHECK (("max_links_per_sector" > 0)),
    CONSTRAINT "universe_settings_positive_sectors" CHECK (("number_of_sectors" > 0)),
    CONSTRAINT "universe_settings_turn_generation_positive" CHECK (("turn_generation_interval_minutes" > 0)),
    CONSTRAINT "universe_settings_turns_per_gen_positive" CHECK (("turns_per_generation" > 0)),
    CONSTRAINT "universe_settings_update_interval_positive" CHECK (("update_interval_minutes" > 0)),
    CONSTRAINT "universe_settings_valid_rates" CHECK ((("igb_interest_rate_per_update" >= (0)::numeric) AND ("igb_loan_rate_per_update" >= (0)::numeric) AND ("planet_interest_rate" >= (0)::numeric) AND ("colonist_production_rate" >= (0)::numeric)))
);


ALTER TABLE "public"."universe_settings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."universe_settings"."last_turn_generation" IS 'Timestamp when turn generation was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_port_regeneration_event" IS 'Timestamp when port regeneration was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_rankings_generation_event" IS 'Timestamp when rankings generation was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_defenses_check_event" IS 'Timestamp when defenses check was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_xenobes_play_event" IS 'Timestamp when xenobes play was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_igb_interest_accumulation_event" IS 'Timestamp when IGB interest accumulation was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_news_generation_event" IS 'Timestamp when news generation was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_planet_production_event" IS 'Timestamp when planet production was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_ships_tow_from_fed_sectors_event" IS 'Timestamp when ships tow from fed sectors was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_sector_defenses_degrade_event" IS 'Timestamp when sector defenses degrade was last executed';



COMMENT ON COLUMN "public"."universe_settings"."last_planetary_apocalypse_event" IS 'Timestamp when planetary apocalypse was last executed';



CREATE TABLE IF NOT EXISTS "public"."universes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "sector_count" integer NOT NULL,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "ai_player_count" integer DEFAULT 0
);


ALTER TABLE "public"."universes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "user_id" "uuid" NOT NULL,
    "is_admin" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."visited" (
    "player_id" "uuid" NOT NULL,
    "sector_id" "uuid" NOT NULL,
    "first_seen" timestamp with time zone DEFAULT "now"(),
    "last_seen" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."visited" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."warps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "universe_id" "uuid" NOT NULL,
    "from_sector" "uuid" NOT NULL,
    "to_sector" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "warps_check" CHECK (("from_sector" <> "to_sector"))
);


ALTER TABLE "public"."warps" OWNER TO "postgres";


ALTER TABLE ONLY "public"."ai_names" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."ai_names_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."ai_action_log"
    ADD CONSTRAINT "ai_action_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_names"
    ADD CONSTRAINT "ai_names_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."ai_names"
    ADD CONSTRAINT "ai_names_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_player_memory"
    ADD CONSTRAINT "ai_player_memory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_players"
    ADD CONSTRAINT "ai_players_name_universe_id_key" UNIQUE ("name", "universe_id");



ALTER TABLE ONLY "public"."ai_players"
    ADD CONSTRAINT "ai_players_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_ranking_history"
    ADD CONSTRAINT "ai_ranking_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bnt_capacity_lookup"
    ADD CONSTRAINT "bnt_capacity_lookup_pkey" PRIMARY KEY ("tech_level");



ALTER TABLE ONLY "public"."combats"
    ADD CONSTRAINT "combats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cron_logs"
    ADD CONSTRAINT "cron_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_pkey" PRIMARY KEY ("player_id", "sector_id");



ALTER TABLE ONLY "public"."planets"
    ADD CONSTRAINT "planets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."player_logs"
    ADD CONSTRAINT "player_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."player_rankings"
    ADD CONSTRAINT "player_rankings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."player_rankings"
    ADD CONSTRAINT "player_rankings_player_id_universe_id_key" UNIQUE ("player_id", "universe_id");



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_universe_id_handle_key" UNIQUE ("universe_id", "handle");



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_user_id_universe_id_key" UNIQUE ("user_id", "universe_id");



ALTER TABLE ONLY "public"."ports"
    ADD CONSTRAINT "ports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ports"
    ADD CONSTRAINT "ports_sector_id_key" UNIQUE ("sector_id");



ALTER TABLE ONLY "public"."ranking_history"
    ADD CONSTRAINT "ranking_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_executions"
    ADD CONSTRAINT "route_executions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_profitability"
    ADD CONSTRAINT "route_profitability_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_profitability"
    ADD CONSTRAINT "route_profitability_route_id_calculated_at_key" UNIQUE ("route_id", "calculated_at");



ALTER TABLE ONLY "public"."route_templates"
    ADD CONSTRAINT "route_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_waypoints"
    ADD CONSTRAINT "route_waypoints_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_waypoints"
    ADD CONSTRAINT "route_waypoints_route_id_sequence_order_key" UNIQUE ("route_id", "sequence_order");



ALTER TABLE ONLY "public"."scans"
    ADD CONSTRAINT "scans_pkey" PRIMARY KEY ("player_id", "sector_id");



ALTER TABLE ONLY "public"."sectors"
    ADD CONSTRAINT "sectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sectors"
    ADD CONSTRAINT "sectors_universe_id_number_key" UNIQUE ("universe_id", "number");



ALTER TABLE ONLY "public"."ships"
    ADD CONSTRAINT "ships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ships"
    ADD CONSTRAINT "ships_player_id_key" UNIQUE ("player_id");



ALTER TABLE ONLY "public"."trade_routes"
    ADD CONSTRAINT "trade_routes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."trade_routes"
    ADD CONSTRAINT "trade_routes_player_id_name_key" UNIQUE ("player_id", "name");



ALTER TABLE ONLY "public"."trades"
    ADD CONSTRAINT "trades_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."universe_settings"
    ADD CONSTRAINT "universe_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."universe_settings"
    ADD CONSTRAINT "universe_settings_unique_per_universe" UNIQUE ("universe_id");



ALTER TABLE ONLY "public"."universes"
    ADD CONSTRAINT "universes_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."universes"
    ADD CONSTRAINT "universes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."visited"
    ADD CONSTRAINT "visited_pkey" PRIMARY KEY ("player_id", "sector_id");



ALTER TABLE ONLY "public"."warps"
    ADD CONSTRAINT "warps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."warps"
    ADD CONSTRAINT "warps_universe_id_from_sector_to_sector_key" UNIQUE ("universe_id", "from_sector", "to_sector");



CREATE UNIQUE INDEX "ai_player_memory_player_id_key" ON "public"."ai_player_memory" USING "btree" ("player_id");



CREATE INDEX "idx_ai_action_log_action" ON "public"."ai_action_log" USING "btree" ("action");



CREATE INDEX "idx_ai_action_log_player_created" ON "public"."ai_action_log" USING "btree" ("player_id", "created_at" DESC);



CREATE INDEX "idx_ai_action_log_universe_created" ON "public"."ai_action_log" USING "btree" ("universe_id", "created_at" DESC);



CREATE INDEX "idx_ai_player_memory_player_id" ON "public"."ai_player_memory" USING "btree" ("player_id");



CREATE INDEX "idx_ai_players_position" ON "public"."ai_players" USING "btree" ("universe_id", "rank_position");



CREATE INDEX "idx_ai_players_universe" ON "public"."ai_players" USING "btree" ("universe_id");



CREATE INDEX "idx_combats_attacker" ON "public"."combats" USING "btree" ("attacker_id");



CREATE INDEX "idx_combats_defender" ON "public"."combats" USING "btree" ("defender_id");



CREATE INDEX "idx_cron_logs_event_type" ON "public"."cron_logs" USING "btree" ("event_type");



CREATE INDEX "idx_cron_logs_status" ON "public"."cron_logs" USING "btree" ("status");



CREATE INDEX "idx_cron_logs_triggered_at" ON "public"."cron_logs" USING "btree" ("triggered_at" DESC);



CREATE INDEX "idx_cron_logs_universe_id" ON "public"."cron_logs" USING "btree" ("universe_id");



CREATE INDEX "idx_planets_credits" ON "public"."planets" USING "btree" ("credits");



CREATE INDEX "idx_planets_last_colonist_growth" ON "public"."planets" USING "btree" ("last_colonist_growth");



CREATE INDEX "idx_planets_last_production" ON "public"."planets" USING "btree" ("last_production");



CREATE INDEX "idx_planets_owner" ON "public"."planets" USING "btree" ("owner_player_id");



CREATE INDEX "idx_planets_owner_player_id" ON "public"."planets" USING "btree" ("owner_player_id");



CREATE INDEX "idx_planets_sector" ON "public"."planets" USING "btree" ("sector_id");



CREATE INDEX "idx_planets_sector_id" ON "public"."planets" USING "btree" ("sector_id");



CREATE INDEX "idx_planets_sector_unclaimed" ON "public"."planets" USING "btree" ("sector_id") WHERE ("owner_player_id" IS NULL);



CREATE INDEX "idx_player_logs_player_time" ON "public"."player_logs" USING "btree" ("player_id", "occurred_at" DESC);



CREATE INDEX "idx_player_rankings_player_id" ON "public"."player_rankings" USING "btree" ("player_id");



CREATE INDEX "idx_player_rankings_position" ON "public"."player_rankings" USING "btree" ("universe_id", "rank_position");



CREATE INDEX "idx_player_rankings_universe" ON "public"."player_rankings" USING "btree" ("universe_id");



CREATE INDEX "idx_player_rankings_universe_id" ON "public"."player_rankings" USING "btree" ("universe_id");



CREATE INDEX "idx_players_current_sector" ON "public"."players" USING "btree" ("current_sector");



CREATE INDEX "idx_players_last_login" ON "public"."players" USING "btree" ("last_login") WHERE ("last_login" IS NOT NULL);



CREATE INDEX "idx_players_score" ON "public"."players" USING "btree" ("score" DESC);



CREATE INDEX "idx_players_universe_id" ON "public"."players" USING "btree" ("universe_id");



CREATE INDEX "idx_players_universe_is_ai" ON "public"."players" USING "btree" ("universe_id", "is_ai") WHERE ("is_ai" = true);



CREATE INDEX "idx_players_user_id" ON "public"."players" USING "btree" ("user_id");



CREATE INDEX "idx_ports_kind" ON "public"."ports" USING "btree" ("kind");



CREATE INDEX "idx_ports_sector_id" ON "public"."ports" USING "btree" ("sector_id");



CREATE INDEX "idx_ports_sector_not_special" ON "public"."ports" USING "btree" ("sector_id", "kind") WHERE ("kind" <> 'special'::"text");



CREATE INDEX "idx_ranking_history_player" ON "public"."ranking_history" USING "btree" ("player_id", "universe_id");



CREATE INDEX "idx_ranking_history_time" ON "public"."ranking_history" USING "btree" ("recorded_at");



CREATE INDEX "idx_route_executions_route" ON "public"."route_executions" USING "btree" ("route_id");



CREATE INDEX "idx_route_executions_status" ON "public"."route_executions" USING "btree" ("status") WHERE ("status" = 'running'::"text");



CREATE INDEX "idx_route_profitability_current" ON "public"."route_profitability" USING "btree" ("route_id") WHERE ("is_current" = true);



CREATE INDEX "idx_route_waypoints_route_order" ON "public"."route_waypoints" USING "btree" ("route_id", "sequence_order");



CREATE INDEX "idx_sectors_last_visited_at" ON "public"."sectors" USING "btree" ("last_visited_at" DESC);



CREATE INDEX "idx_sectors_last_visited_by" ON "public"."sectors" USING "btree" ("last_visited_by");



CREATE INDEX "idx_sectors_owner" ON "public"."sectors" USING "btree" ("owner_player_id") WHERE ("owner_player_id" IS NOT NULL);



CREATE INDEX "idx_sectors_universe_id" ON "public"."sectors" USING "btree" ("universe_id");



CREATE INDEX "idx_sectors_universe_number" ON "public"."sectors" USING "btree" ("universe_id", "number");



CREATE INDEX "idx_ships_player_id" ON "public"."ships" USING "btree" ("player_id");



CREATE INDEX "idx_trade_routes_active" ON "public"."trade_routes" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_trade_routes_player_active" ON "public"."trade_routes" USING "btree" ("player_id", "is_active");



CREATE INDEX "idx_trade_routes_player_universe" ON "public"."trade_routes" USING "btree" ("player_id", "universe_id");



CREATE INDEX "idx_trade_routes_universe_id" ON "public"."trade_routes" USING "btree" ("universe_id");



CREATE INDEX "idx_trades_at" ON "public"."trades" USING "btree" ("at");



CREATE INDEX "idx_trades_player_id" ON "public"."trades" USING "btree" ("player_id");



CREATE INDEX "idx_universe_settings_created_at" ON "public"."universe_settings" USING "btree" ("created_at");



CREATE INDEX "idx_universe_settings_universe_id" ON "public"."universe_settings" USING "btree" ("universe_id");



CREATE INDEX "idx_warps_from_sector" ON "public"."warps" USING "btree" ("from_sector");



CREATE INDEX "idx_warps_to_sector" ON "public"."warps" USING "btree" ("to_sector");



CREATE OR REPLACE TRIGGER "planet_ownership_trigger" AFTER INSERT OR DELETE OR UPDATE OF "owner_player_id", "base_built" ON "public"."planets" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_update_sector_ownership"();



COMMENT ON TRIGGER "planet_ownership_trigger" ON "public"."planets" IS 'Automatically updates sector ownership when planet bases change';



CREATE OR REPLACE TRIGGER "players_mark_last_visitor_trg" AFTER UPDATE OF "current_sector" ON "public"."players" FOR EACH ROW EXECUTE FUNCTION "public"."trg_mark_last_visitor"();



CREATE OR REPLACE TRIGGER "trg_track_sector_visit" AFTER UPDATE OF "current_sector" ON "public"."players" FOR EACH ROW EXECUTE FUNCTION "public"."track_sector_visit"();



CREATE OR REPLACE TRIGGER "trg_trades_compat_sync" BEFORE INSERT ON "public"."trades" FOR EACH ROW EXECUTE FUNCTION "public"."trades_compat_sync"();



CREATE OR REPLACE TRIGGER "trigger_update_player_score" BEFORE UPDATE ON "public"."players" FOR EACH ROW EXECUTE FUNCTION "public"."update_player_score"();



CREATE OR REPLACE TRIGGER "trigger_update_player_score_from_planet" AFTER INSERT OR UPDATE ON "public"."planets" FOR EACH ROW EXECUTE FUNCTION "public"."update_player_score_from_planet"();



CREATE OR REPLACE TRIGGER "trigger_update_player_score_from_ship" AFTER UPDATE ON "public"."ships" FOR EACH ROW EXECUTE FUNCTION "public"."update_player_score_from_ship"();



CREATE OR REPLACE TRIGGER "warp_limit_trigger" BEFORE INSERT ON "public"."warps" FOR EACH ROW EXECUTE FUNCTION "public"."check_warp_degree"();



ALTER TABLE ONLY "public"."ai_action_log"
    ADD CONSTRAINT "ai_action_log_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_action_log"
    ADD CONSTRAINT "ai_action_log_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_player_memory"
    ADD CONSTRAINT "ai_player_memory_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_players"
    ADD CONSTRAINT "ai_players_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_ranking_history"
    ADD CONSTRAINT "ai_ranking_history_ai_player_id_fkey" FOREIGN KEY ("ai_player_id") REFERENCES "public"."ai_players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_ranking_history"
    ADD CONSTRAINT "ai_ranking_history_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."combats"
    ADD CONSTRAINT "combats_attacker_id_fkey" FOREIGN KEY ("attacker_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."combats"
    ADD CONSTRAINT "combats_defender_id_fkey" FOREIGN KEY ("defender_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cron_logs"
    ADD CONSTRAINT "cron_logs_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_sector_id_fkey" FOREIGN KEY ("sector_id") REFERENCES "public"."sectors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."planets"
    ADD CONSTRAINT "planets_owner_player_id_fkey" FOREIGN KEY ("owner_player_id") REFERENCES "public"."players"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."planets"
    ADD CONSTRAINT "planets_sector_id_fkey" FOREIGN KEY ("sector_id") REFERENCES "public"."sectors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_logs"
    ADD CONSTRAINT "player_logs_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_rankings"
    ADD CONSTRAINT "player_rankings_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_rankings"
    ADD CONSTRAINT "player_rankings_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_current_sector_fkey" FOREIGN KEY ("current_sector") REFERENCES "public"."sectors"("id");



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ports"
    ADD CONSTRAINT "ports_sector_id_fkey" FOREIGN KEY ("sector_id") REFERENCES "public"."sectors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ranking_history"
    ADD CONSTRAINT "ranking_history_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ranking_history"
    ADD CONSTRAINT "ranking_history_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_executions"
    ADD CONSTRAINT "route_executions_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_executions"
    ADD CONSTRAINT "route_executions_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "public"."trade_routes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_profitability"
    ADD CONSTRAINT "route_profitability_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "public"."trade_routes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_waypoints"
    ADD CONSTRAINT "route_waypoints_port_id_fkey" FOREIGN KEY ("port_id") REFERENCES "public"."ports"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_waypoints"
    ADD CONSTRAINT "route_waypoints_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "public"."trade_routes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."scans"
    ADD CONSTRAINT "scans_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."scans"
    ADD CONSTRAINT "scans_sector_id_fkey" FOREIGN KEY ("sector_id") REFERENCES "public"."sectors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sectors"
    ADD CONSTRAINT "sectors_last_player_visited_fkey" FOREIGN KEY ("last_player_visited") REFERENCES "public"."players"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sectors"
    ADD CONSTRAINT "sectors_last_visited_by_fkey" FOREIGN KEY ("last_visited_by") REFERENCES "public"."players"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sectors"
    ADD CONSTRAINT "sectors_owner_player_id_fkey" FOREIGN KEY ("owner_player_id") REFERENCES "public"."players"("id");



ALTER TABLE ONLY "public"."sectors"
    ADD CONSTRAINT "sectors_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ships"
    ADD CONSTRAINT "ships_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."trade_routes"
    ADD CONSTRAINT "trade_routes_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."trade_routes"
    ADD CONSTRAINT "trade_routes_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."trades"
    ADD CONSTRAINT "trades_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."trades"
    ADD CONSTRAINT "trades_port_id_fkey" FOREIGN KEY ("port_id") REFERENCES "public"."ports"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."universe_settings"
    ADD CONSTRAINT "universe_settings_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."universe_settings"
    ADD CONSTRAINT "universe_settings_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."universe_settings"
    ADD CONSTRAINT "universe_settings_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."visited"
    ADD CONSTRAINT "visited_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."visited"
    ADD CONSTRAINT "visited_sector_id_fkey" FOREIGN KEY ("sector_id") REFERENCES "public"."sectors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."warps"
    ADD CONSTRAINT "warps_from_sector_fkey" FOREIGN KEY ("from_sector") REFERENCES "public"."sectors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."warps"
    ADD CONSTRAINT "warps_to_sector_fkey" FOREIGN KEY ("to_sector") REFERENCES "public"."sectors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."warps"
    ADD CONSTRAINT "warps_universe_id_fkey" FOREIGN KEY ("universe_id") REFERENCES "public"."universes"("id") ON DELETE CASCADE;



CREATE POLICY "Admins can update universe settings" ON "public"."universe_settings" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."user_id" = "auth"."uid"()) AND ("up"."is_admin" = true)))));



CREATE POLICY "Admins can view universe settings" ON "public"."universe_settings" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."user_id" = "auth"."uid"()) AND ("up"."is_admin" = true)))));



CREATE POLICY "Cron logs are viewable by everyone" ON "public"."cron_logs" FOR SELECT USING (true);



CREATE POLICY "Only admins can modify universe settings" ON "public"."universe_settings" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."is_admin" = true)))));



CREATE POLICY "Only service role can insert cron logs" ON "public"."cron_logs" FOR INSERT WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Universe settings are viewable by everyone" ON "public"."universe_settings" FOR SELECT USING (true);



CREATE POLICY "Users can insert own trade routes" ON "public"."trade_routes" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "trade_routes"."player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can insert own trades" ON "public"."trades" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "trades"."player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can insert own visited" ON "public"."visited" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "visited"."player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can insert planets" ON "public"."planets" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "planets"."owner_player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update own planets" ON "public"."planets" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "planets"."owner_player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update own players" ON "public"."players" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own ships" ON "public"."ships" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "ships"."player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update own trade routes" ON "public"."trade_routes" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "trade_routes"."player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view all planets" ON "public"."planets" FOR SELECT USING (true);



CREATE POLICY "Users can view all ports" ON "public"."ports" FOR SELECT USING (true);



CREATE POLICY "Users can view all rankings" ON "public"."player_rankings" FOR SELECT USING (true);



CREATE POLICY "Users can view all sectors" ON "public"."sectors" FOR SELECT USING (true);



CREATE POLICY "Users can view all universes" ON "public"."universes" FOR SELECT USING (true);



CREATE POLICY "Users can view own players" ON "public"."players" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own ships" ON "public"."ships" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "ships"."player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view own trade routes" ON "public"."trade_routes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "trade_routes"."player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view own trades" ON "public"."trades" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "trades"."player_id") AND ("p"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view own visited" ON "public"."visited" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."players" "p"
  WHERE (("p"."id" = "visited"."player_id") AND ("p"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."ai_action_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_names" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_player_memory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_players" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_ranking_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bnt_capacity_lookup" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."combats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cron_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "deny_all_anon" ON "public"."ai_action_log" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."ai_names" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."ai_player_memory" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."ai_players" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."ai_ranking_history" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."bnt_capacity_lookup" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."combats" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."favorites" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."ranking_history" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."route_executions" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."route_profitability" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."route_templates" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."route_waypoints" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."scans" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."user_profiles" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_anon" ON "public"."warps" TO "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."ai_action_log" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."ai_names" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."ai_player_memory" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."ai_players" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."ai_ranking_history" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."bnt_capacity_lookup" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."combats" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."favorites" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."ranking_history" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."route_executions" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."route_profitability" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."route_templates" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."route_waypoints" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."scans" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."user_profiles" TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "deny_all_authenticated" ON "public"."warps" TO "authenticated" USING (false) WITH CHECK (false);



ALTER TABLE "public"."favorites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."planets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."player_rankings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."players" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ranking_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."route_executions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."route_profitability" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."route_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."route_waypoints" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."scans" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sectors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ships" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."trade_routes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."trades" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."universe_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."universes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."visited" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."warps" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."add_one_link_for_sector"("p_universe_name" "text", "p_sector_number" integer, "p_max_per_sector" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."add_one_link_for_sector"("p_universe_name" "text", "p_sector_number" integer, "p_max_per_sector" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_one_link_for_sector"("p_universe_name" "text", "p_sector_number" integer, "p_max_per_sector" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."add_route_waypoint"("p_user_id" "uuid", "p_route_id" "uuid", "p_port_id" "uuid", "p_action_type" "text", "p_resource" "text", "p_quantity" integer, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."add_route_waypoint"("p_user_id" "uuid", "p_route_id" "uuid", "p_port_id" "uuid", "p_action_type" "text", "p_resource" "text", "p_quantity" integer, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_route_waypoint"("p_user_id" "uuid", "p_route_id" "uuid", "p_port_id" "uuid", "p_action_type" "text", "p_resource" "text", "p_quantity" integer, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_basic_action"("ai_player" "record", "action" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_basic_action"("ai_player" "record", "action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_basic_action"("ai_player" "record", "action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_buy_fighters"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_buy_fighters"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_buy_fighters"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_claim_planet"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_claim_planet"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_claim_planet"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_emergency_trade"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_emergency_trade"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_emergency_trade"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_execute_action"("ai_player" "record", "ai_memory" "record", "action" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_execute_action"("ai_player" "record", "ai_memory" "record", "action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_execute_action"("ai_player" "record", "ai_memory" "record", "action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_execute_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_execute_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_execute_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_execute_real_action"("ai_player" "record", "ai_memory" "record", "action" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_execute_real_action"("ai_player" "record", "ai_memory" "record", "action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_execute_real_action"("ai_player" "record", "ai_memory" "record", "action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_make_decision"("p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_make_decision"("p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_make_decision"("p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_make_decision"("ai_player" "record", "ai_memory" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_make_decision"("ai_player" "record", "ai_memory" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_make_decision"("ai_player" "record", "ai_memory" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_make_decision_debug"("p_player_id" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_make_decision_debug"("p_player_id" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_make_decision_debug"("p_player_id" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_make_simple_decision"("ai_player" "record", "ai_memory" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_make_simple_decision"("ai_player" "record", "ai_memory" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_make_simple_decision"("ai_player" "record", "ai_memory" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_manage_planets"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_manage_planets"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_manage_planets"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_optimize_trading"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_optimize_trading"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_optimize_trading"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_patrol_territory"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_patrol_territory"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_patrol_territory"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_ship_upgrade"("p_ship_id" "uuid", "p_attr" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_ship_upgrade"("p_ship_id" "uuid", "p_attr" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_ship_upgrade"("p_ship_id" "uuid", "p_attr" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_strategic_explore"("ai_player" "record", "ai_memory" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_strategic_explore"("ai_player" "record", "ai_memory" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_strategic_explore"("ai_player" "record", "ai_memory" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_strategic_move"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_strategic_move"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_strategic_move"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_upgrade_engines"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_upgrade_engines"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_upgrade_engines"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_upgrade_ship"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_upgrade_ship"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_upgrade_ship"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_upgrade_weapons"("ai_player" "record") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_upgrade_weapons"("ai_player" "record") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_upgrade_weapons"("ai_player" "record") TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_federation_rules"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."apply_federation_rules"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_federation_rules"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_igb_interest"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."apply_igb_interest"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_igb_interest"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_trade"("p_user_id" "uuid", "p_port_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."auto_trade"("p_user_id" "uuid", "p_port_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_trade"("p_user_id" "uuid", "p_port_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."build_planet_base"("p_user_id" "uuid", "p_planet_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."build_planet_base"("p_user_id" "uuid", "p_planet_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."build_planet_base"("p_user_id" "uuid", "p_planet_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_bnt_capacity"("tech_level" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_bnt_capacity"("tech_level" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_bnt_capacity"("tech_level" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_economic_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_economic_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_economic_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_exploration_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_exploration_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_exploration_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_military_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_military_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_military_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_player_score"("p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_player_score"("p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_player_score"("p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_price_multiplier"("current_stock" integer, "port_kind" "text", "base_stock" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_price_multiplier"("current_stock" integer, "port_kind" "text", "base_stock" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_price_multiplier"("current_stock" integer, "port_kind" "text", "base_stock" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_route_profitability"("p_user_id" "uuid", "p_route_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_route_profitability"("p_user_id" "uuid", "p_route_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_route_profitability"("p_user_id" "uuid", "p_route_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_ship_avg_tech_level"("p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_ship_avg_tech_level"("p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_ship_avg_tech_level"("p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_ship_capacity"("p_ship_id" "uuid", "p_capacity_type" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_ship_capacity"("p_ship_id" "uuid", "p_capacity_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_ship_capacity"("p_ship_id" "uuid", "p_capacity_type" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_territorial_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_territorial_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_territorial_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_total_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_total_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_total_score"("p_player_id" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_ai_health"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_ai_health"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_ai_health"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_sector_ownership"("p_sector_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_sector_ownership"("p_sector_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_sector_ownership"("p_sector_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_sector_permission"("p_sector_id" "uuid", "p_player_id" "uuid", "p_action" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_sector_permission"("p_sector_id" "uuid", "p_player_id" "uuid", "p_action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_sector_permission"("p_sector_id" "uuid", "p_player_id" "uuid", "p_action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_warp_degree"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_warp_degree"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_warp_degree"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_orphaned_player_data"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_orphaned_player_data"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_orphaned_player_data"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_ai_players"("p_universe_id" "uuid", "p_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."create_ai_players"("p_universe_id" "uuid", "p_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_ai_players"("p_universe_id" "uuid", "p_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text", "p_movement_type" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text", "p_movement_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text", "p_movement_type" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_universe"("p_name" "text", "p_sector_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."create_universe"("p_name" "text", "p_sector_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_universe"("p_name" "text", "p_sector_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_universe_default_settings"("p_universe_id" "uuid", "p_created_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_universe_default_settings"("p_universe_id" "uuid", "p_created_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_universe_default_settings"("p_universe_id" "uuid", "p_created_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cron_run_ai_actions"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."cron_run_ai_actions"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cron_run_ai_actions"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cron_run_ai_actions_safe"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."cron_run_ai_actions_safe"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cron_run_ai_actions_safe"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."degrade_sector_defenses"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."degrade_sector_defenses"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."degrade_sector_defenses"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."densify_universe_links"("p_universe_id" "uuid", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."densify_universe_links"("p_universe_id" "uuid", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."densify_universe_links"("p_universe_id" "uuid", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."densify_universe_links_by_id"("p_universe_id" "uuid", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."densify_universe_links_by_id"("p_universe_id" "uuid", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."densify_universe_links_by_id"("p_universe_id" "uuid", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."densify_universe_links_by_name"("p_universe_name" "text", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."densify_universe_links_by_name"("p_universe_name" "text", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."densify_universe_links_by_name"("p_universe_name" "text", "p_target_min" integer, "p_max_per_sector" integer, "p_max_attempts" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."deploy_mines"("p_player_id" "uuid", "p_sector_id" "uuid", "p_universe_id" "uuid", "p_torpedoes_to_use" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."deploy_mines"("p_player_id" "uuid", "p_sector_id" "uuid", "p_universe_id" "uuid", "p_torpedoes_to_use" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."deploy_mines"("p_player_id" "uuid", "p_sector_id" "uuid", "p_universe_id" "uuid", "p_torpedoes_to_use" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."destroy_universe"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."destroy_universe"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."destroy_universe"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."diagnose_ai_players"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."diagnose_ai_players"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."diagnose_ai_players"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."emergency_warp"("p_player_id" "uuid", "p_universe_id" "uuid", "p_target_sector_number" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."emergency_warp"("p_player_id" "uuid", "p_universe_id" "uuid", "p_target_sector_number" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."emergency_warp"("p_player_id" "uuid", "p_universe_id" "uuid", "p_target_sector_number" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."execute_trade_route"("p_user_id" "uuid", "p_route_id" "uuid", "p_max_iterations" integer, "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."execute_trade_route"("p_user_id" "uuid", "p_route_id" "uuid", "p_max_iterations" integer, "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."execute_trade_route"("p_user_id" "uuid", "p_route_id" "uuid", "p_max_iterations" integer, "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_engine_upgrade"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_engine_upgrade"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_engine_upgrade"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_hyperspace"("p_id" "uuid", "p_target_sector_number" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."game_hyperspace"("p_id" "uuid", "p_target_sector_number" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_hyperspace"("p_id" "uuid", "p_target_sector_number" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer, "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer, "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer, "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_planet_store"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."game_planet_store"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_planet_store"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."game_planet_withdraw"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."game_planet_withdraw"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_planet_withdraw"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."game_repair"("p_user_id" "uuid", "p_hull" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."game_repair"("p_user_id" "uuid", "p_hull" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_repair"("p_user_id" "uuid", "p_hull" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."game_ship_rename"("p_user_id" "uuid", "p_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."game_ship_rename"("p_user_id" "uuid", "p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_ship_rename"("p_user_id" "uuid", "p_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_trade"("p_user_id" "uuid", "p_port_id" "uuid", "p_action" "text", "p_resource" "text", "p_qty" integer, "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_trade"("p_user_id" "uuid", "p_port_id" "uuid", "p_action" "text", "p_resource" "text", "p_qty" integer, "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_trade"("p_user_id" "uuid", "p_port_id" "uuid", "p_action" "text", "p_resource" "text", "p_qty" integer, "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_upgrade"("p_user_id" "uuid", "p_item" "text", "p_qty" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."game_upgrade"("p_user_id" "uuid", "p_item" "text", "p_qty" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_upgrade"("p_user_id" "uuid", "p_item" "text", "p_qty" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."game_upgrade_ship"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_upgrade_ship"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_upgrade_ship"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."game_upgrade_ship_attr"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."game_upgrade_ship_attr"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."game_upgrade_ship_attr"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_ai_name"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_ai_name"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_ai_name"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_turns_for_universe"("p_universe_id" "uuid", "p_turns_to_add" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."generate_turns_for_universe"("p_universe_id" "uuid", "p_turns_to_add" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_turns_for_universe"("p_universe_id" "uuid", "p_turns_to_add" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_universe_news"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_universe_news"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_universe_news"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ai_activity_summary"("p_universe_id" "uuid", "p_hours" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_ai_activity_summary"("p_universe_id" "uuid", "p_hours" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ai_activity_summary"("p_universe_id" "uuid", "p_hours" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ai_dashboard_stats"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_ai_dashboard_stats"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ai_dashboard_stats"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ai_debug_snapshot"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_ai_debug_snapshot"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ai_debug_snapshot"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ai_performance_metrics"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_ai_performance_metrics"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ai_performance_metrics"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ai_players"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_ai_players"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ai_players"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ai_statistics"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_ai_statistics"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ai_statistics"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cron_log_summary"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_cron_log_summary"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cron_log_summary"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cron_logs"("p_universe_id" "uuid", "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_cron_logs"("p_universe_id" "uuid", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cron_logs"("p_universe_id" "uuid", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_emergency_warp_status"("p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_emergency_warp_status"("p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_emergency_warp_status"("p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_first_available_universe"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_first_available_universe"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_first_available_universe"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_leaderboard"("p_universe_id" "uuid", "p_limit" integer, "p_ai_only" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."get_leaderboard"("p_universe_id" "uuid", "p_limit" integer, "p_ai_only" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_leaderboard"("p_universe_id" "uuid", "p_limit" integer, "p_ai_only" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_leaderboard_stats"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_leaderboard_stats"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_leaderboard_stats"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_next_scheduled_events"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_next_scheduled_events"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_next_scheduled_events"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_planet_owner_player_id"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_planet_owner_player_id"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_planet_owner_player_id"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_player_for_user_in_universe"("p_user_id" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_player_for_user_in_universe"("p_user_id" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_player_for_user_in_universe"("p_user_id" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_player_inventory"("p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_player_inventory"("p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_player_inventory"("p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_player_trade_routes"("p_user_id" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_player_trade_routes"("p_user_id" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_player_trade_routes"("p_user_id" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_sector_degrees_by_name"("p_universe_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_sector_degrees_by_name"("p_universe_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_sector_degrees_by_name"("p_universe_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_sector_mine_info"("p_sector_id" "uuid", "p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_sector_mine_info"("p_sector_id" "uuid", "p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_sector_mine_info"("p_sector_id" "uuid", "p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ship_capacity"("p_ship_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_ship_capacity"("p_ship_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ship_capacity"("p_ship_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ship_capacity_data"("p_ship_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_ship_capacity_data"("p_ship_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ship_capacity_data"("p_ship_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_universe_settings"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_universe_settings"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_universe_settings"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_user_admin"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_user_admin"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_user_admin"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."list_universes"() TO "anon";
GRANT ALL ON FUNCTION "public"."list_universes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_universes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action_type" "text", "p_outcome" "text", "p_details" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action_type" "text", "p_outcome" "text", "p_details" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action_type" "text", "p_outcome" "text", "p_details" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text", "p_outcome" "text", "p_message" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text", "p_outcome" "text", "p_message" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_ai_action"("p_player_id" "uuid", "p_universe_id" "uuid", "p_action" "text", "p_outcome" "text", "p_message" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_ai_action"("p_universe_id" "uuid", "p_player_id" "uuid", "p_action" "text", "p_target_sector_id" "uuid", "p_target_planet_id" "uuid", "p_credits_before" bigint, "p_credits_after" bigint, "p_turns_before" integer, "p_turns_after" integer, "p_outcome" "text", "p_message" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."log_ai_action"("p_universe_id" "uuid", "p_player_id" "uuid", "p_action" "text", "p_target_sector_id" "uuid", "p_target_planet_id" "uuid", "p_credits_before" bigint, "p_credits_after" bigint, "p_turns_before" integer, "p_turns_after" integer, "p_outcome" "text", "p_message" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_ai_action"("p_universe_id" "uuid", "p_player_id" "uuid", "p_action" "text", "p_target_sector_id" "uuid", "p_target_planet_id" "uuid", "p_credits_before" bigint, "p_credits_after" bigint, "p_turns_before" integer, "p_turns_after" integer, "p_outcome" "text", "p_message" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_ai_debug"("p_player_id" "uuid", "p_universe_id" "uuid", "p_step" "text", "p_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."log_ai_debug"("p_player_id" "uuid", "p_universe_id" "uuid", "p_step" "text", "p_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_ai_debug"("p_player_id" "uuid", "p_universe_id" "uuid", "p_step" "text", "p_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_cron_event"("p_universe_id" "uuid", "p_event_type" "text", "p_event_name" "text", "p_status" "text", "p_message" "text", "p_execution_time_ms" integer, "p_metadata" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."log_cron_event"("p_universe_id" "uuid", "p_event_type" "text", "p_event_name" "text", "p_status" "text", "p_message" "text", "p_execution_time_ms" integer, "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_cron_event"("p_universe_id" "uuid", "p_event_type" "text", "p_event_name" "text", "p_status" "text", "p_message" "text", "p_execution_time_ms" integer, "p_metadata" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_sector_last_visited"("p_player_id" "uuid", "p_sector_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_sector_last_visited"("p_player_id" "uuid", "p_sector_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_sector_last_visited"("p_player_id" "uuid", "p_sector_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."purchase_special_port_items"("p_player_id" "uuid", "p_purchases" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."purchase_special_port_items"("p_player_id" "uuid", "p_purchases" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."purchase_special_port_items"("p_player_id" "uuid", "p_purchases" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_all_player_scores"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_all_player_scores"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_all_player_scores"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."regen_turns_for_universe"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."regen_turns_for_universe"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."regen_turns_for_universe"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."remove_mines_from_sector"("p_sector_id" "uuid", "p_universe_id" "uuid", "p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."remove_mines_from_sector"("p_sector_id" "uuid", "p_universe_id" "uuid", "p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_mines_from_sector"("p_sector_id" "uuid", "p_universe_id" "uuid", "p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."rename_planet"("p_user_id" "uuid", "p_planet_id" "uuid", "p_new_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rename_planet"("p_user_id" "uuid", "p_planet_id" "uuid", "p_new_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rename_planet"("p_user_id" "uuid", "p_planet_id" "uuid", "p_new_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rename_sector"("p_sector_id" "uuid", "p_player_id" "uuid", "p_new_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rename_sector"("p_sector_id" "uuid", "p_player_id" "uuid", "p_new_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rename_sector"("p_sector_id" "uuid", "p_player_id" "uuid", "p_new_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."run_ai_actions_working"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."run_ai_actions_working"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_ai_actions_working"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."run_ai_player_actions"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."run_ai_player_actions"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_ai_player_actions"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."run_ai_player_actions_debug"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."run_ai_player_actions_debug"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_ai_player_actions_debug"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."run_apocalypse_tick"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."run_apocalypse_tick"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_apocalypse_tick"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."run_defenses_checks"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."run_defenses_checks"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_defenses_checks"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."run_enhanced_ai_actions"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."run_enhanced_ai_actions"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_enhanced_ai_actions"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."run_planet_production"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."run_planet_production"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_planet_production"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."run_xenobes_turn"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."run_xenobes_turn"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_xenobes_turn"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."simple_ai_debug"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."simple_ai_debug"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."simple_ai_debug"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."test_ai_debug_system"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."test_ai_debug_system"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_ai_debug_system"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."test_cron_function"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."test_cron_function"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_cron_function"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."test_destroy_response_format"() TO "anon";
GRANT ALL ON FUNCTION "public"."test_destroy_response_format"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_destroy_response_format"() TO "service_role";



GRANT ALL ON FUNCTION "public"."test_destroy_universe"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."test_destroy_universe"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_destroy_universe"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."test_diagnostic"() TO "anon";
GRANT ALL ON FUNCTION "public"."test_diagnostic"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_diagnostic"() TO "service_role";



GRANT ALL ON FUNCTION "public"."test_enhanced_ai_debug"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."test_enhanced_ai_debug"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_enhanced_ai_debug"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."tow_ships_from_fed"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."tow_ships_from_fed"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tow_ships_from_fed"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."track_sector_visit"() TO "anon";
GRANT ALL ON FUNCTION "public"."track_sector_visit"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."track_sector_visit"() TO "service_role";



GRANT ALL ON FUNCTION "public"."track_turn_spent"("p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."track_turn_spent"("p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."track_turn_spent"("p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."track_turn_spent"("p_player_id" "uuid", "p_turns_spent" integer, "p_action_type" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."track_turn_spent"("p_player_id" "uuid", "p_turns_spent" integer, "p_action_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."track_turn_spent"("p_player_id" "uuid", "p_turns_spent" integer, "p_action_type" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."trade_by_type"("p_user_id" "uuid", "p_port_id" "uuid", "p_resource" "text", "p_action" "text", "p_quantity" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."trade_by_type"("p_user_id" "uuid", "p_port_id" "uuid", "p_resource" "text", "p_action" "text", "p_quantity" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."trade_by_type"("p_user_id" "uuid", "p_port_id" "uuid", "p_resource" "text", "p_action" "text", "p_quantity" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."trades_compat_sync"() TO "anon";
GRANT ALL ON FUNCTION "public"."trades_compat_sync"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trades_compat_sync"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_mark_last_visitor"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_mark_last_visitor"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_mark_last_visitor"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_update_sector_ownership"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_update_sector_ownership"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_update_sector_ownership"() TO "service_role";



GRANT ALL ON FUNCTION "public"."universe_exists"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."universe_exists"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."universe_exists"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_ai_memory"("p_player_id" "uuid", "p_action" "text", "p_success" boolean, "p_message" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_ai_memory"("p_player_id" "uuid", "p_action" "text", "p_success" boolean, "p_message" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_ai_memory"("p_player_id" "uuid", "p_action" "text", "p_success" boolean, "p_message" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_fighters_percent" integer, "p_torpedoes_percent" integer, "p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_fighters_percent" integer, "p_torpedoes_percent" integer, "p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_planet_production_allocation"("p_planet_id" "uuid", "p_ore_percent" integer, "p_organics_percent" integer, "p_goods_percent" integer, "p_energy_percent" integer, "p_fighters_percent" integer, "p_torpedoes_percent" integer, "p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_player_last_login"("p_player_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_player_last_login"("p_player_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_player_last_login"("p_player_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_player_score"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_player_score"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_player_score"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_player_score_from_planet"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_player_score_from_planet"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_player_score_from_planet"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_player_score_from_ship"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_player_score_from_ship"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_player_score_from_ship"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_port_stock_dynamics"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_port_stock_dynamics"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_port_stock_dynamics"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_port_stock_dynamics"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_port_stock_dynamics"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_port_stock_dynamics"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_route_stats"("p_route_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_route_stats"("p_route_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_route_stats"("p_route_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_scheduler_timestamp"("p_universe_id" "uuid", "p_event_type" "text", "p_timestamp" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."update_scheduler_timestamp"("p_universe_id" "uuid", "p_event_type" "text", "p_timestamp" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_scheduler_timestamp"("p_universe_id" "uuid", "p_event_type" "text", "p_timestamp" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_sector_ownership"("p_sector_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_sector_ownership"("p_sector_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_sector_ownership"("p_sector_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_sector_rules"("p_sector_id" "uuid", "p_player_id" "uuid", "p_allow_attacking" boolean, "p_allow_trading" "text", "p_allow_planet_creation" "text", "p_allow_sector_defense" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_sector_rules"("p_sector_id" "uuid", "p_player_id" "uuid", "p_allow_attacking" boolean, "p_allow_trading" "text", "p_allow_planet_creation" "text", "p_allow_sector_defense" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_sector_rules"("p_sector_id" "uuid", "p_player_id" "uuid", "p_allow_attacking" boolean, "p_allow_trading" "text", "p_allow_planet_creation" "text", "p_allow_sector_defense" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_universe_economy"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_universe_economy"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_universe_economy"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_universe_rankings"("p_universe_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_universe_rankings"("p_universe_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_universe_rankings"("p_universe_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_universe_settings"("p_universe_id" "uuid", "p_settings" "jsonb", "p_updated_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_universe_settings"("p_universe_id" "uuid", "p_settings" "jsonb", "p_updated_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_universe_settings"("p_universe_id" "uuid", "p_settings" "jsonb", "p_updated_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."user_owns_planet"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."user_owns_planet"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."user_owns_planet"("p_user_id" "uuid", "p_universe_id" "uuid", "p_planet_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_route_waypoints"("p_route_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_route_waypoints"("p_route_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_route_waypoints"("p_route_id" "uuid") TO "service_role";


















GRANT ALL ON TABLE "public"."ai_action_log" TO "anon";
GRANT ALL ON TABLE "public"."ai_action_log" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_action_log" TO "service_role";



GRANT ALL ON TABLE "public"."ai_names" TO "anon";
GRANT ALL ON TABLE "public"."ai_names" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_names" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ai_names_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ai_names_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ai_names_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."ai_player_memory" TO "anon";
GRANT ALL ON TABLE "public"."ai_player_memory" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_player_memory" TO "service_role";



GRANT ALL ON TABLE "public"."ai_players" TO "anon";
GRANT ALL ON TABLE "public"."ai_players" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_players" TO "service_role";



GRANT ALL ON TABLE "public"."ai_ranking_history" TO "anon";
GRANT ALL ON TABLE "public"."ai_ranking_history" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_ranking_history" TO "service_role";



GRANT ALL ON TABLE "public"."bnt_capacity_lookup" TO "anon";
GRANT ALL ON TABLE "public"."bnt_capacity_lookup" TO "authenticated";
GRANT ALL ON TABLE "public"."bnt_capacity_lookup" TO "service_role";



GRANT ALL ON TABLE "public"."combats" TO "anon";
GRANT ALL ON TABLE "public"."combats" TO "authenticated";
GRANT ALL ON TABLE "public"."combats" TO "service_role";



GRANT ALL ON TABLE "public"."cron_logs" TO "anon";
GRANT ALL ON TABLE "public"."cron_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."cron_logs" TO "service_role";



GRANT ALL ON TABLE "public"."favorites" TO "anon";
GRANT ALL ON TABLE "public"."favorites" TO "authenticated";
GRANT ALL ON TABLE "public"."favorites" TO "service_role";



GRANT ALL ON TABLE "public"."planets" TO "anon";
GRANT ALL ON TABLE "public"."planets" TO "authenticated";
GRANT ALL ON TABLE "public"."planets" TO "service_role";



GRANT ALL ON TABLE "public"."player_logs" TO "anon";
GRANT ALL ON TABLE "public"."player_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."player_logs" TO "service_role";



GRANT ALL ON TABLE "public"."player_rankings" TO "anon";
GRANT ALL ON TABLE "public"."player_rankings" TO "authenticated";
GRANT ALL ON TABLE "public"."player_rankings" TO "service_role";



GRANT ALL ON TABLE "public"."players" TO "anon";
GRANT ALL ON TABLE "public"."players" TO "authenticated";
GRANT ALL ON TABLE "public"."players" TO "service_role";



GRANT ALL ON TABLE "public"."ports" TO "anon";
GRANT ALL ON TABLE "public"."ports" TO "authenticated";
GRANT ALL ON TABLE "public"."ports" TO "service_role";



GRANT ALL ON TABLE "public"."ranking_history" TO "anon";
GRANT ALL ON TABLE "public"."ranking_history" TO "authenticated";
GRANT ALL ON TABLE "public"."ranking_history" TO "service_role";



GRANT ALL ON TABLE "public"."route_executions" TO "anon";
GRANT ALL ON TABLE "public"."route_executions" TO "authenticated";
GRANT ALL ON TABLE "public"."route_executions" TO "service_role";



GRANT ALL ON TABLE "public"."route_profitability" TO "anon";
GRANT ALL ON TABLE "public"."route_profitability" TO "authenticated";
GRANT ALL ON TABLE "public"."route_profitability" TO "service_role";



GRANT ALL ON TABLE "public"."route_templates" TO "anon";
GRANT ALL ON TABLE "public"."route_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."route_templates" TO "service_role";



GRANT ALL ON TABLE "public"."route_waypoints" TO "anon";
GRANT ALL ON TABLE "public"."route_waypoints" TO "authenticated";
GRANT ALL ON TABLE "public"."route_waypoints" TO "service_role";



GRANT ALL ON TABLE "public"."scans" TO "anon";
GRANT ALL ON TABLE "public"."scans" TO "authenticated";
GRANT ALL ON TABLE "public"."scans" TO "service_role";



GRANT ALL ON TABLE "public"."sectors" TO "anon";
GRANT ALL ON TABLE "public"."sectors" TO "authenticated";
GRANT ALL ON TABLE "public"."sectors" TO "service_role";



GRANT ALL ON TABLE "public"."ships" TO "anon";
GRANT ALL ON TABLE "public"."ships" TO "authenticated";
GRANT ALL ON TABLE "public"."ships" TO "service_role";



GRANT ALL ON TABLE "public"."trade_routes" TO "anon";
GRANT ALL ON TABLE "public"."trade_routes" TO "authenticated";
GRANT ALL ON TABLE "public"."trade_routes" TO "service_role";



GRANT ALL ON TABLE "public"."trades" TO "anon";
GRANT ALL ON TABLE "public"."trades" TO "authenticated";
GRANT ALL ON TABLE "public"."trades" TO "service_role";



GRANT ALL ON TABLE "public"."universe_settings" TO "anon";
GRANT ALL ON TABLE "public"."universe_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."universe_settings" TO "service_role";



GRANT ALL ON TABLE "public"."universes" TO "anon";
GRANT ALL ON TABLE "public"."universes" TO "authenticated";
GRANT ALL ON TABLE "public"."universes" TO "service_role";



GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."visited" TO "anon";
GRANT ALL ON TABLE "public"."visited" TO "authenticated";
GRANT ALL ON TABLE "public"."visited" TO "service_role";



GRANT ALL ON TABLE "public"."warps" TO "anon";
GRANT ALL ON TABLE "public"."warps" TO "authenticated";
GRANT ALL ON TABLE "public"."warps" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























\unrestrict nrJdW0riCvilLfd5zOJOfGY4RIelRJ3NtPzHNXOMMM9GqGwZMlAZBIKMWwYaUAT

RESET ALL;
