
> CREATE OR REPLACE FUNCTION "public"."add_route_waypoint"("p_user_id" "uuid", "p_route_id" "uuid", "p_port_id" "uuid", "p_action_type" "text", "p_resource" "text" DEFAULT NULL::"text", "p_quantity" integer DEFAULT 0, "p_notes" "text" 
DEFAULT NULL::"text") RETURNS json
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
  
  
> CREATE OR REPLACE FUNCTION "public"."calculate_economic_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS integer
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_score INTEGER := 0;
    v_credits INTEGER;
    v_trading_volume INTEGER;
    v_port_influence INTEGER;
  BEGIN
    -- Get player credits
    SELECT COALESCE(credits, 0) INTO v_credits
    FROM players
    WHERE id = p_player_id AND universe_id = p_universe_id;
    
    -- Calculate trading volume (sum of all trade values)
    SELECT COALESCE(SUM(
      CASE 
        WHEN action = 'buy' THEN qty * price
        WHEN action = 'sell' THEN qty * price
        ELSE 0
      END
    ), 0) INTO v_trading_volume
    FROM trades t
    JOIN players p ON t.player_id = p.id
    WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
    
    -- Calculate port influence (number of unique ports traded at)
    SELECT COUNT(DISTINCT port_id) INTO v_port_influence
    FROM trades t
    JOIN players p ON t.player_id = p.id
    WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
    
    -- Economic score formula: credits + (trading_volume / 1000) + (port_influence * 100)
    v_score := v_credits + (v_trading_volume / 1000) + (v_port_influence * 100);
    
    RETURN GREATEST(0, v_score);
  END;
  $$;
  
  
  ALTER FUNCTION "public"."calculate_economic_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."calculate_exploration_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS integer
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_score INTEGER := 0;
    v_sectors_visited INTEGER;
    v_warp_discoveries INTEGER;
    v_universe_size INTEGER;
  BEGIN
    -- Count unique sectors visited
    SELECT COUNT(DISTINCT v.sector_id) INTO v_sectors_visited
    FROM visited v
    JOIN players p ON v.player_id = p.id
    WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
    
    -- Count warp connections discovered (future feature)
    v_warp_discoveries := 0;
    
    -- Get universe size for percentage calculation
    SELECT COUNT(*) INTO v_universe_size
    FROM sectors
    WHERE universe_id = p_universe_id;
    
    -- Exploration score formula: (sectors_visited * 50) + (percentage * 1000) + discoveries
    v_score := (v_sectors_visited * 50) + ((v_sectors_visited * 1000) / GREATEST(1, v_universe_size)) + v_warp_discoveries;
    
    RETURN GREATEST(0, v_score);
  END;
  $$;
  
  
  ALTER FUNCTION "public"."calculate_exploration_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."calculate_military_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS integer
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_score INTEGER := 0;
    v_ship_levels INTEGER;
    v_combat_victories INTEGER;
  BEGIN
    -- Calculate ship level score (sum of all upgrade levels)
    SELECT COALESCE(
      (engine_lvl + comp_lvl + sensor_lvl + shield_lvl + hull_lvl) * 100, 
      0
    ) INTO v_ship_levels
    FROM ships s
    JOIN players p ON s.player_id = p.id
    WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
    
    -- Future: Add combat victories when combat system is implemented
    v_combat_victories := 0;
    
    -- Military score formula: ship_levels + (combat_victories * 500)
    v_score := v_ship_levels + (v_combat_victories * 500);
    
    RETURN GREATEST(0, v_score);
  END;
  $$;
  
  
  ALTER FUNCTION "public"."calculate_military_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."calculate_price_multiplier"("current_stock" integer, "base_stock" integer DEFAULT 1000000000) RETURNS numeric
      LANGUAGE "plpgsql" IMMUTABLE
      AS $$
  BEGIN
    -- Price range: 0.8x to 1.5x based on stock levels
    -- Low stock = higher prices, high stock = lower prices
    -- Use logarithmic scaling to make small changes negligible for low-level players
    
    IF current_stock <= 0 THEN
      RETURN 1.5; -- Maximum price when out of stock
    END IF;
    
    -- Logarithmic scaling: log10(stock/base_stock)
    -- This means 10% stock = ~1.4x price, 50% stock = ~1.0x price, 200% stock = ~0.8x price
    DECLARE
      stock_ratio NUMERIC := current_stock::NUMERIC / base_stock;
      log_factor NUMERIC := LOG(10, GREATEST(stock_ratio, 0.1)); -- Clamp to avoid log(0)
      multiplier NUMERIC;
    BEGIN
      -- Scale log factor to price range (0.8 to 1.5)
      multiplier := 1.5 - (log_factor + 1) * 0.35; -- log(0.1) â‰ˆ -1, log(10) â‰ˆ 1
      multiplier := GREATEST(0.8, LEAST(1.5, multiplier)); -- Clamp to range
      RETURN multiplier;
    END;
  END;
  $$;
  
  
  ALTER FUNCTION "public"."calculate_price_multiplier"("current_stock" integer, "base_stock" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."calculate_route_profitability"("p_user_id" "uuid", "p_route_id" "uuid") RETURNS json
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
  
  
> CREATE OR REPLACE FUNCTION "public"."calculate_territorial_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS integer
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_score INTEGER := 0;
    v_planets_owned INTEGER;
    v_planet_development INTEGER;
    v_sectors_controlled INTEGER;
  BEGIN
    -- Count planets owned
    SELECT COUNT(*) INTO v_planets_owned
    FROM planets pl
    JOIN sectors s ON pl.sector_id = s.id
    WHERE pl.owner_player_id = p_player_id AND s.universe_id = p_universe_id;
    
    -- Calculate planet development (sum of planet levels/upgrades)
    -- For now, just count planets. Future: add planet upgrade levels
    v_planet_development := v_planets_owned * 100;
    
    -- Count unique sectors with owned planets
    SELECT COUNT(DISTINCT s.id) INTO v_sectors_controlled
    FROM planets pl
    JOIN sectors s ON pl.sector_id = s.id
    WHERE pl.owner_player_id = p_player_id AND s.universe_id = p_universe_id;
    
    -- Territorial score formula: (planets * 1000) + (sectors * 500) + development
    v_score := (v_planets_owned * 1000) + (v_sectors_controlled * 500) + v_planet_development;
    
    RETURN GREATEST(0, v_score);
  END;
  $$;
  
  
  ALTER FUNCTION "public"."calculate_territorial_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."calculate_total_score"("p_player_id" "uuid", "p_universe_id" "uuid") RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_economic INTEGER;
    v_territorial INTEGER;
    v_military INTEGER;
    v_exploration INTEGER;
    v_total INTEGER;
  BEGIN
    -- Calculate individual scores
    v_economic := calculate_economic_score(p_player_id, p_universe_id);
    v_territorial := calculate_territorial_score(p_player_id, p_universe_id);
    v_military := calculate_military_score(p_player_id, p_universe_id);
    v_exploration := calculate_exploration_score(p_player_id, p_universe_id);
    
    -- Calculate total with weights: Economic(40%), Territorial(25%), Military(20%), Exploration(15%)
    v_total := (v_economic * 0.40) + (v_territorial * 0.25) + (v_military * 0.20) + (v_exploration * 0.15);
    
    RETURN json_build_object(
      'economic', v_economic,
      'territorial', v_territorial,
      'military', v_military,
      'exploration', v_exploration,
      'total', v_total
    );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."calculate_total_score"("p_player_id" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."check_warp_count"() RETURNS "trigger"
      LANGUAGE "plpgsql"
      AS $$
  DECLARE
    warp_count INTEGER;
  BEGIN
    -- Count existing warps for this universe
    SELECT COUNT(*) INTO warp_count
    FROM warps
    WHERE universe_id = NEW.universe_id;
    
    -- Check if adding this warp would exceed the limit
    IF warp_count >= 15 THEN
      RAISE EXCEPTION 'Maximum warp limit reached: Universe % already has 15 warps', NEW.universe_id;
    END IF;
    
    RETURN NEW;
  END;
  $$;
  
  
  ALTER FUNCTION "public"."check_warp_count"() OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text" DEFAULT NULL::"text") RETURNS json
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
  
  
> CREATE OR REPLACE FUNCTION "public"."create_trade_route"("p_user_id" "uuid", "p_universe_id" "uuid", "p_name" "text", "p_description" "text" DEFAULT NULL::"text", "p_movement_type" "text" DEFAULT 'warp'::"text") RETURNS json
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
  
  
> CREATE OR REPLACE FUNCTION "public"."create_universe"("p_name" "text" DEFAULT 'Alpha'::"text", "p_port_density" numeric DEFAULT 0.30, "p_planet_density" numeric DEFAULT 0.25, "p_sector_count" integer DEFAULT 500) RETURNS "jsonb"
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_universe_id UUID;
    v_sector_count INTEGER;
    v_port_count INTEGER;
    v_planet_count INTEGER;
  BEGIN
    -- Validate inputs
    IF p_port_density < 0 OR p_port_density > 1 THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_density', 'message', 'Port density must be between 0 and 1'));
    END IF;
    
    IF p_planet_density < 0 OR p_planet_density > 1 THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_density', 'message', 'Planet density must be between 0 and 1'));
    END IF;
    
    IF p_sector_count < 1 OR p_sector_count > 1000 THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_sectors', 'message', 'Sector count must be between 1 and 1000'));
    END IF;
  
    -- Check if universe with this name already exists
    IF EXISTS (SELECT 1 FROM universes WHERE name = p_name) THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_exists', 'message', 'A universe with this name already exists'));
    END IF;
  
    -- Create universe
    INSERT INTO universes (name, sector_count) VALUES (p_name, p_sector_count) RETURNING id INTO v_universe_id;
    
    -- Create sectors (0 to p_sector_count)
    INSERT INTO sectors (universe_id, number)
    SELECT v_universe_id, generate_series(0, p_sector_count);
    
    GET DIAGNOSTICS v_sector_count = ROW_COUNT;
    
    -- Create backbone warps (0â†”1â†”2â†”...â†”p_sector_count) - bidirectional
    INSERT INTO warps (universe_id, from_sector, to_sector)
    SELECT 
      v_universe_id,
      s1.id as from_sector,
      s2.id as to_sector
    FROM sectors s1, sectors s2
    WHERE s1.universe_id = v_universe_id 
      AND s2.universe_id = v_universe_id
      AND s1.number = s2.number - 1
    UNION ALL
    SELECT 
      v_universe_id,
      s2.id as from_sector,
      s1.id as to_sector
    FROM sectors s1, sectors s2
    WHERE s1.universe_id = v_universe_id 
      AND s2.universe_id = v_universe_id
      AND s1.number = s2.number - 1
    ON CONFLICT (universe_id, from_sector, to_sector) DO NOTHING;
    
    -- Create random warps (additional connections)
    INSERT INTO warps (universe_id, from_sector, to_sector)
    SELECT 
      v_universe_id,
      s1.id as from_sector,
      s2.id as to_sector
    FROM sectors s1, sectors s2
    WHERE s1.universe_id = v_universe_id 
      AND s2.universe_id = v_universe_id
      AND s1.number != s2.number
      AND random() < 0.05 -- 5% chance for random warps
    ON CONFLICT (universe_id, from_sector, to_sector) DO NOTHING;
    
    -- Create Sol Hub (Sector 0) with special port
    INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
    SELECT 
      s.id,
      'special',
      0, 0, 0, 0,
      10.00, 12.00, 20.00, 6.00
    FROM sectors s
    WHERE s.universe_id = v_universe_id AND s.number = 0;
    
    -- Create commodity ports with configurable density
    INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
    SELECT 
      port_data.sector_id,
      port_data.kind,
      CASE WHEN port_data.kind = 'ore' THEN 1000000000 ELSE 0 END as ore,
      CASE WHEN port_data.kind = 'organics' THEN 1000000000 ELSE 0 END as organics,
      CASE WHEN port_data.kind = 'goods' THEN 1000000000 ELSE 0 END as goods,
      CASE WHEN port_data.kind = 'energy' THEN 1000000000 ELSE 0 END as energy,
      10.00 as price_ore,
      12.00 as price_organics,
      20.00 as price_goods,
      6.00 as price_energy
    FROM (
      SELECT 
        s.id as sector_id,
        CASE floor(random() * 4)
          WHEN 0 THEN 'ore'
          WHEN 1 THEN 'organics' 
          WHEN 2 THEN 'goods'
          WHEN 3 THEN 'energy'
        END as kind
      FROM sectors s
      WHERE s.universe_id = v_universe_id 
        AND s.number > 0  -- Exclude sector 0
        AND random() < p_port_density
    ) port_data;
    
    GET DIAGNOSTICS v_port_count = ROW_COUNT;
    
    -- Create planets with configurable density
    INSERT INTO planets (sector_id, name, owner_player_id)
    SELECT 
      s.id,
      'Planet ' || (ROW_NUMBER() OVER (ORDER BY s.id)),
      NULL
    FROM sectors s
    WHERE s.universe_id = v_universe_id 
      AND s.number > 0
      AND random() < p_planet_density;
    
    GET DIAGNOSTICS v_planet_count = ROW_COUNT;
    
    -- Return success with statistics
    RETURN jsonb_build_object(
      'ok', true,
      'universe_id', v_universe_id,
      'name', p_name,
      'sectors', v_sector_count + 1, -- +1 for sector 0
      'ports', v_port_count + 1, -- +1 for Sol Hub special port
      'planets', v_planet_count,
      'settings', jsonb_build_object(
        'port_density', p_port_density,
        'planet_density', p_planet_density,
        'sector_count', p_sector_count
      )
    );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."create_universe"("p_name" "text", "p_port_density" numeric, "p_planet_density" numeric, "p_sector_count" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."create_universe"("p_name" "text" DEFAULT 'Alpha'::"text", "p_port_density" numeric DEFAULT 0.30, "p_planet_density" numeric DEFAULT 0.25, "p_sector_count" integer DEFAULT 500, "p_ai_player_count" 
integer DEFAULT 0) RETURNS "jsonb"
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_universe_id UUID;
    v_sector_count INTEGER;
    v_port_count INTEGER;
    v_planet_count INTEGER;
  BEGIN
    -- Validate inputs
    IF p_port_density < 0 OR p_port_density > 1 THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_density', 'message', 'Port density must be between 0 and 1'));
    END IF;
    
    IF p_planet_density < 0 OR p_planet_density > 1 THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_density', 'message', 'Planet density must be between 0 and 1'));
    END IF;
    
    IF p_sector_count < 1 OR p_sector_count > 1000 THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_sectors', 'message', 'Sector count must be between 1 and 1000'));
    END IF;
  
    -- Check if universe with this name already exists
    IF EXISTS (SELECT 1 FROM universes WHERE name = p_name) THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_exists', 'message', 'A universe with this name already exists'));
    END IF;
  
    -- Create universe
    INSERT INTO universes (name, sector_count) VALUES (p_name, p_sector_count) RETURNING id INTO v_universe_id;
    
    -- Create sectors (0 to p_sector_count)
    INSERT INTO sectors (universe_id, number)
    SELECT v_universe_id, generate_series(0, p_sector_count);
    
    GET DIAGNOSTICS v_sector_count = ROW_COUNT;
    
    -- Create backbone warps (0â†”1â†”2â†”...â†”p_sector_count) - bidirectional
    INSERT INTO warps (universe_id, from_sector, to_sector)
    SELECT 
      v_universe_id,
      s1.id as from_sector,
      s2.id as to_sector
    FROM sectors s1, sectors s2
    WHERE s1.universe_id = v_universe_id 
      AND s2.universe_id = v_universe_id
      AND s1.number = s2.number - 1
    UNION ALL
    SELECT 
      v_universe_id,
      s2.id as from_sector,
      s1.id as to_sector
    FROM sectors s1, sectors s2
    WHERE s1.universe_id = v_universe_id 
      AND s2.universe_id = v_universe_id
      AND s1.number = s2.number - 1
    ON CONFLICT (universe_id, from_sector, to_sector) DO NOTHING;
    
    -- Create random warps (additional connections) - capped at 10 total warps
    -- NOTE: Future warp editor will allow players to add up to 15 total warps
    WITH random_warp_candidates AS (
      SELECT 
        v_universe_id as universe_id,
        s1.id as from_sector,
        s2.id as to_sector,
        ROW_NUMBER() OVER (ORDER BY random()) as rn
      FROM sectors s1, sectors s2
      WHERE s1.universe_id = v_universe_id 
        AND s2.universe_id = v_universe_id
        AND s1.number != s2.number
        AND random() < 0.05 -- 5% chance for random warps
    ),
    current_warp_count AS (
      SELECT COUNT(*) as count
      FROM warps w 
      WHERE w.universe_id = v_universe_id
    )
    INSERT INTO warps (universe_id, from_sector, to_sector)
    SELECT 
      universe_id,
      from_sector,
      to_sector
    FROM random_warp_candidates
    WHERE rn <= GREATEST(0, 10 - (SELECT count FROM current_warp_count))
    ON CONFLICT (universe_id, from_sector, to_sector) DO NOTHING;
    
    -- Create Sol Hub (Sector 0) with special port
    INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
    SELECT 
      s.id,
      'special',
      0, 0, 0, 0,
      10.00, 12.00, 20.00, 6.00
    FROM sectors s
    WHERE s.universe_id = v_universe_id AND s.number = 0;
    
    -- Create commodity ports with configurable density
    INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy)
    SELECT 
      port_data.sector_id,
      port_data.kind,
      CASE WHEN port_data.kind = 'ore' THEN 1000000000 ELSE 0 END as ore,
      CASE WHEN port_data.kind = 'organics' THEN 1000000000 ELSE 0 END as organics,
      CASE WHEN port_data.kind = 'goods' THEN 1000000000 ELSE 0 END as goods,
      CASE WHEN port_data.kind = 'energy' THEN 1000000000 ELSE 0 END as energy,
      10.00 as price_ore,
      12.00 as price_organics,
      20.00 as price_goods,
      6.00 as price_energy
    FROM (
      SELECT 
        s.id as sector_id,
        CASE floor(random() * 4)
          WHEN 0 THEN 'ore'
          WHEN 1 THEN 'organics' 
          WHEN 2 THEN 'goods'
          WHEN 3 THEN 'energy'
        END as kind
      FROM sectors s
      WHERE s.universe_id = v_universe_id 
        AND s.number > 0  -- Exclude sector 0
        AND random() < p_port_density
    ) port_data;
    
    GET DIAGNOSTICS v_port_count = ROW_COUNT;
    
    -- Create planets with configurable density
    INSERT INTO planets (sector_id, name, owner_player_id)
    SELECT 
      s.id,
      'Planet ' || (ROW_NUMBER() OVER (ORDER BY s.id)),
      NULL
    FROM sectors s
    WHERE s.universe_id = v_universe_id 
      AND s.number > 0
      AND random() < p_planet_density;
    
    GET DIAGNOSTICS v_planet_count = ROW_COUNT;
    
    -- Create AI players if requested
    IF p_ai_player_count > 0 THEN
      INSERT INTO ai_players (universe_id, name, ai_type, economic_score, territorial_score, military_score, exploration_score, total_score)
      SELECT 
        v_universe_id,
        CASE 
          WHEN ai_type = 'trader' THEN 'Trader_AI_' || generate_series(1, p_ai_player_count / 4)
          WHEN ai_type = 'explorer' THEN 'Explorer_AI_' || generate_series(1, p_ai_player_count / 4)
          WHEN ai_type = 'military' THEN 'Military_AI_' || generate_series(1, p_ai_player_count / 4)
          ELSE 'Balanced_AI_' || generate_series(1, p_ai_player_count / 4)
        END,
        ai_type,
        CASE ai_type
          WHEN 'trader' THEN 5000 + (random() * 2000)::INTEGER
          WHEN 'explorer' THEN 1000 + (random() * 1000)::INTEGER
          WHEN 'military' THEN 2000 + (random() * 1500)::INTEGER
          ELSE 3000 + (random() * 1500)::INTEGER
        END,
        CASE ai_type
          WHEN 'trader' THEN 1000 + (random() * 500)::INTEGER
          WHEN 'explorer' THEN 2000 + (random() * 1000)::INTEGER
          WHEN 'military' THEN 3000 + (random() * 1500)::INTEGER
          ELSE 2000 + (random() * 1000)::INTEGER
        END,
        CASE ai_type
          WHEN 'trader' THEN 500 + (random() * 500)::INTEGER
          WHEN 'explorer' THEN 1000 + (random() * 500)::INTEGER
          WHEN 'military' THEN 2000 + (random() * 1000)::INTEGER
          ELSE 1000 + (random() * 750)::INTEGER
        END,
        CASE ai_type
          WHEN 'trader' THEN 500 + (random() * 500)::INTEGER
          WHEN 'explorer' THEN 2000 + (random() * 1000)::INTEGER
          WHEN 'military' THEN 1000 + (random() * 500)::INTEGER
          ELSE 1500 + (random() * 750)::INTEGER
        END,
        0 -- total_score will be calculated by ranking system
      FROM (
        SELECT 'trader' as ai_type
        UNION ALL SELECT 'explorer'
        UNION ALL SELECT 'military'
        UNION ALL SELECT 'balanced'
      ) ai_types
      CROSS JOIN generate_series(1, GREATEST(1, p_ai_player_count / 4)) as ai_count;
    END IF;
    
    -- Return success with statistics
    RETURN jsonb_build_object(
      'ok', true,
      'universe_id', v_universe_id,
      'name', p_name,
      'sectors', v_sector_count + 1, -- +1 for sector 0
      'ports', v_port_count + 1, -- +1 for Sol Hub special port
      'planets', v_planet_count,
      'ai_players', p_ai_player_count,
      'settings', jsonb_build_object(
        'port_density', p_port_density,
        'planet_density', p_planet_density,
        'sector_count', p_sector_count,
        'ai_player_count', p_ai_player_count
      )
    );
  END;
> CREATE OR REPLACE FUNCTION "public"."destroy_universe"("p_universe_id" "uuid") RETURNS "jsonb"
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_universe_name TEXT;
    v_player_count INTEGER;
    v_ship_count INTEGER;
  BEGIN
    -- Get universe name for logging
    SELECT name INTO v_universe_name FROM universes WHERE id = p_universe_id;
    
    IF v_universe_name IS NULL THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_not_found', 'message', 'Universe not found'));
    END IF;
    
    -- Count affected entities
    SELECT COUNT(*) INTO v_player_count FROM players WHERE universe_id = p_universe_id;
    SELECT COUNT(*) INTO v_ship_count FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
    
    -- Delete all data in dependency order
    DELETE FROM trades WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
    DELETE FROM combats WHERE attacker_id IN (SELECT id FROM players WHERE universe_id = p_universe_id) 
      OR defender_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
    DELETE FROM visited WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    DELETE FROM scans WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    DELETE FROM favorites WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    DELETE FROM planets WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    DELETE FROM ports WHERE sector_id IN (SELECT id FROM sectors WHERE universe_id = p_universe_id);
    DELETE FROM ships WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
    DELETE FROM inventories WHERE player_id IN (SELECT id FROM players WHERE universe_id = p_universe_id);
    DELETE FROM players WHERE universe_id = p_universe_id;
    DELETE FROM warps WHERE universe_id = p_universe_id;
    DELETE FROM sectors WHERE universe_id = p_universe_id;
    DELETE FROM universes WHERE id = p_universe_id;
    
    -- Return success with statistics
    RETURN jsonb_build_object(
      'ok', true,
      'universe_name', v_universe_name,
      'players_deleted', v_player_count,
      'ships_deleted', v_ship_count,
      'message', 'Universe destroyed successfully'
    );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."destroy_universe"("p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."execute_trade_route"("p_user_id" "uuid", "p_route_id" "uuid", "p_max_iterations" integer DEFAULT 1) RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
      v_player_id UUID;
      v_route RECORD;
      v_execution_id UUID;
      v_result JSON;
  BEGIN
      -- Verify route ownership and get route details
      SELECT tr.*, p.id as player_id
      INTO v_route
      FROM trade_routes tr
      JOIN players p ON tr.player_id = p.id
      WHERE tr.id = p_route_id AND p.user_id = p_user_id;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', json_build_object('code', 'route_not_found', 'message', 'Route not found or access denied'));
      END IF;
      
      -- Check if route has waypoints
      IF NOT EXISTS(SELECT 1 FROM route_waypoints WHERE route_id = p_route_id) THEN
          RETURN json_build_object('error', json_build_object('code', 'no_waypoints', 'message', 'Route has no waypoints'));
      END IF;
      
      -- Create execution record
      INSERT INTO route_executions (route_id, player_id, status)
      VALUES (p_route_id, v_player_id, 'running')
      RETURNING id INTO v_execution_id;
      
      -- Update route last executed time
      UPDATE trade_routes 
      SET last_executed_at = now(), updated_at = now()
      WHERE id = p_route_id;
      
      RETURN json_build_object(
          'ok', true,
          'execution_id', v_execution_id,
          'message', 'Route execution started'
      );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."execute_trade_route"("p_user_id" "uuid", "p_route_id" "uuid", "p_max_iterations" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."execute_trade_route"("p_user_id" "uuid", "p_route_id" "uuid", "p_max_iterations" integer DEFAULT 1, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
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
      -- Get player info
      IF p_universe_id IS NOT NULL THEN
          SELECT p.*, s.engine_lvl INTO v_player
          FROM players p
          JOIN ships s ON p.id = s.player_id
          WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
      ELSE
          SELECT p.*, s.engine_lvl INTO v_player
          FROM players p
          JOIN ships s ON p.id = s.player_id
          WHERE p.user_id = p_user_id;
      END IF;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
      END IF;
      
      v_player_id := v_player.id;
      v_turns_before := v_player.turns;
      v_credits_before := v_player.credits;
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
      
      -- Calculate required turns based on movement type
      DECLARE
          v_required_turns INTEGER;
      BEGIN
          IF v_movement_type = 'warp' THEN
              v_required_turns := 3; -- 1 move + 1 trade + 1 return
          ELSE -- realspace
              v_required_turns := (v_distance * 2) + 1; -- distance turns each way + 1 trade
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
              v_log := v_log || 'Start port trade successful' || E'\n';
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
      v_log := v_log || 'Moved to target port' || E'\n';
      
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
      v_log := v_log || 'Target port trade successful' || E'\n';
      
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
      v_log := v_log || 'Returned to start port' || E'\n';
      
      -- Get final player state
      SELECT turns, credits INTO v_turns_after, v_credits_after
      FROM players
      WHERE id = v_player_id;
      
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
> CREATE OR REPLACE FUNCTION "public"."game_engine_upgrade"("p_user_id" "uuid") RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_player_id UUID;
    v_credits BIGINT;
    v_engine_lvl INT;
    v_cost INT;
  BEGIN
    SELECT p.id, p.credits INTO v_player_id, v_credits FROM players p WHERE p.user_id = p_user_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
    END IF;
  
    SELECT engine_lvl INTO v_engine_lvl FROM ships WHERE player_id = v_player_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
    END IF;
  
    v_cost := 500 * (v_engine_lvl + 1);
    IF v_credits < v_cost THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_funds','message','Insufficient credits'));
    END IF;
  
    UPDATE players SET credits = credits - v_cost WHERE id = v_player_id;
    UPDATE ships SET engine_lvl = engine_lvl + 1 WHERE player_id = v_player_id;
  
    SELECT p.credits, s.engine_lvl INTO v_credits, v_engine_lvl
    FROM players p JOIN ships s ON s.player_id = p.id
    WHERE p.id = v_player_id;
  
    RETURN json_build_object('ok', true, 'credits', v_credits, 'ship', json_build_object('engine_lvl', v_engine_lvl));
  END; $$;
  
  
  ALTER FUNCTION "public"."game_engine_upgrade"("p_user_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer) RETURNS json
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
    -- Load player, current sector, ship
    SELECT p.id, p.turns, p.current_sector
    INTO v_player_id, v_turns, v_current_sector_id
    FROM players p WHERE p.user_id = p_user_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
    END IF;
  
    SELECT s.number INTO v_current_number FROM sectors s WHERE s.id = v_current_sector_id;
  
    SELECT s.id INTO v_target_sector_id FROM sectors s
    JOIN universes u ON u.id = s.universe_id AND u.name = 'Alpha'
    WHERE s.number = p_target_sector_number;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','invalid_target','message','Target sector not found'));
    END IF;
  
    SELECT engine_lvl INTO v_engine_lvl FROM ships WHERE player_id = v_player_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
    END IF;
  
    v_cost := GREATEST(1, CEIL( abs(v_current_number - p_target_sector_number)::NUMERIC / GREATEST(1, v_engine_lvl) )::INT);
    IF v_turns < v_cost THEN
      RETURN json_build_object('error', json_build_object('code','insufficient_turns','message','Not enough turns'));
    END IF;
  
    UPDATE players SET current_sector = v_target_sector_id, turns = turns - v_cost WHERE id = v_player_id;
  
    -- Upsert visited
    INSERT INTO visited (player_id, sector_id, first_seen, last_seen)
    VALUES (v_player_id, v_target_sector_id, now(), now())
    ON CONFLICT (player_id, sector_id) DO UPDATE SET last_seen = EXCLUDED.last_seen;
  
    SELECT turns INTO v_turns FROM players WHERE id = v_player_id;
  
    RETURN json_build_object('ok', true, 'player', json_build_object('current_sector_number', p_target_sector_number, 'turns', v_turns));
  END; $$;
  
  
  ALTER FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_hyperspace"("p_user_id" "uuid", "p_target_sector_number" integer, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
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
    v_cost := GREATEST(1, CEIL(ABS(p_target_sector_number - v_current_number) / GREATEST(1, v_engine_lvl)));
  
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
  
  
> CREATE OR REPLACE FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer) RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
      v_player RECORD;
      v_current_sector RECORD;
      v_target_sector RECORD;
      v_warp_exists BOOLEAN;
      v_result JSON;
  BEGIN
      -- Get player info
      SELECT p.*, s.number as current_sector_number
      INTO v_player
      FROM players p
      JOIN sectors s ON p.current_sector = s.id
      WHERE p.user_id = p_user_id;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', 'Player not found');
      END IF;
      
      -- Check if player has turns
      IF v_player.turns < 1 THEN
          RETURN json_build_object('error', 'Insufficient turns');
      END IF;
      
      -- Get target sector
      SELECT * INTO v_target_sector
      FROM sectors s
      JOIN universes u ON s.universe_id = u.id
      WHERE u.name = 'Alpha' AND s.number = p_to_sector_number;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', 'Target sector not found');
      END IF;
      
      -- Check if warp exists from current to target
      SELECT EXISTS(
          SELECT 1 FROM warps w
          WHERE w.from_sector = v_player.current_sector
          AND w.to_sector = v_target_sector.id
      ) INTO v_warp_exists;
      
      IF NOT v_warp_exists THEN
          RETURN json_build_object('error', 'No warp connection to target sector');
      END IF;
      
      -- Perform the move
      UPDATE players 
      SET current_sector = v_target_sector.id, turns = turns - 1
      WHERE id = v_player.id;
      
      -- Return success
      RETURN json_build_object(
          'ok', true,
          'player', json_build_object(
              'current_sector', v_target_sector.id,
              'turns', v_player.turns - 1
          )
      );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
      v_player RECORD;
      v_current_sector RECORD;
      v_target_sector RECORD;
      v_warp_exists BOOLEAN;
      v_result JSON;
  BEGIN
      -- Get player info - filter by universe if provided
      IF p_universe_id IS NOT NULL THEN
          SELECT p.*, s.number as current_sector_number
          INTO v_player
          FROM players p
          JOIN sectors s ON p.current_sector = s.id
          WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
      ELSE
          SELECT p.*, s.number as current_sector_number
          INTO v_player
          FROM players p
          JOIN sectors s ON p.current_sector = s.id
          WHERE p.user_id = p_user_id;
      END IF;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', 'Player not found');
      END IF;
      
      -- Check if player has turns
      IF v_player.turns <= 0 THEN
          RETURN json_build_object('error', 'No turns remaining');
      END IF;
      
      -- Get current sector info
      SELECT * INTO v_current_sector
      FROM sectors
      WHERE id = v_player.current_sector;
      
      -- Get target sector info - filter by universe if provided
      IF p_universe_id IS NOT NULL THEN
          SELECT * INTO v_target_sector
          FROM sectors
          WHERE number = p_to_sector_number AND universe_id = p_universe_id;
      ELSE
          SELECT * INTO v_target_sector
          FROM sectors
          WHERE number = p_to_sector_number;
      END IF;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', 'Target sector not found');
      END IF;
      
      -- Check if warp exists from current to target
      SELECT EXISTS(
          SELECT 1 FROM warps w
          WHERE w.from_sector = v_player.current_sector
          AND w.to_sector = v_target_sector.id
      ) INTO v_warp_exists;
      
      IF NOT v_warp_exists THEN
          RETURN json_build_object('error', 'No warp connection to target sector');
      END IF;
      
      -- Perform the move
      UPDATE players 
      SET current_sector = v_target_sector.id, turns = turns - 1
      WHERE id = v_player.id;
      
      -- Return success with updated player info
      SELECT json_build_object(
          'ok', true,
          'message', 'Move successful',
          'player', json_build_object(
              'id', v_player.id,
              'handle', v_player.handle,
              'turns', v_player.turns - 1,
              'current_sector', v_target_sector.id,
              'current_sector_number', v_target_sector.number
          )
      ) INTO v_result;
      
      RETURN v_result;
      
  EXCEPTION
      WHEN OTHERS THEN
          RETURN json_build_object('error', 'Move operation failed: ' || SQLERRM);
  END;
  $$;
  
  
  ALTER FUNCTION "public"."game_move"("p_user_id" "uuid", "p_to_sector_number" integer, "p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text" DEFAULT 'Colony'::"text") RETURNS json
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
  
  
> CREATE OR REPLACE FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text" DEFAULT 'Colony'::"text", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
      LANGUAGE "plpgsql"
      AS $$
  DECLARE
      v_player_id UUID;
      v_sector_id UUID;
      v_universe_id UUID;
      v_planet_id UUID;
  BEGIN
      -- Find player by auth user_id - filter by universe if provided
      IF p_universe_id IS NOT NULL THEN
          SELECT p.id, s.universe_id
          INTO v_player_id, v_universe_id
          FROM players p
          JOIN sectors s ON p.current_sector = s.id
          WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
      ELSE
          SELECT p.id, s.universe_id
          INTO v_player_id, v_universe_id
          FROM players p
          JOIN sectors s ON p.current_sector = s.id
          WHERE p.user_id = p_user_id;
      END IF;
  
      IF v_player_id IS NULL THEN
          RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
      END IF;
  
      -- Find sector
      SELECT id INTO v_sector_id
      FROM sectors
      WHERE universe_id = v_universe_id AND number = p_sector_number;
  
      IF v_sector_id IS NULL THEN
          RETURN json_build_object('error', json_build_object('code', 'sector_not_found', 'message', 'Sector not found'));
      END IF;
  
      -- Check if player is in the correct sector
      IF NOT EXISTS (
          SELECT 1 FROM players 
          WHERE id = v_player_id AND current_sector = v_sector_id
      ) THEN
          RETURN json_build_object('error', json_build_object('code', 'wrong_sector', 'message', 'Player not in target sector'));
      END IF;
  
      -- Check if planet already exists
      IF EXISTS (
          SELECT 1 FROM planets 
          WHERE sector_id = v_sector_id
      ) THEN
          RETURN json_build_object('error', json_build_object('code', 'planet_exists', 'message', 'Planet already exists in this sector'));
      END IF;
  
      -- Create planet
      INSERT INTO planets (sector_id, name, owner_player_id)
      VALUES (v_sector_id, p_name, v_player_id)
      RETURNING id INTO v_planet_id;
  
      RETURN json_build_object(
          'ok', true,
          'planet_id', v_planet_id,
          'name', p_name,
          'sector_number', p_sector_number
      );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."game_planet_claim"("p_user_id" "uuid", "p_sector_number" integer, "p_name" "text", "p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_planet_store"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $_$
  DECLARE
      v_player_id UUID;
      v_qty INT;
      v_field TEXT;
  BEGIN
      IF p_qty IS NULL OR p_qty <= 0 THEN
          RAISE EXCEPTION 'invalid_qty' USING ERRCODE = 'P0001';
      END IF;
  
      SELECT id INTO v_player_id FROM players WHERE user_id = p_user_id;
      IF v_player_id IS NULL THEN RAISE EXCEPTION 'player_not_found' USING ERRCODE='P0001'; END IF;
  
      -- Ownership
      IF NOT EXISTS (SELECT 1 FROM planets WHERE id = p_planet AND owner_player_id = v_player_id) THEN
          RAISE EXCEPTION 'not_owner' USING ERRCODE='P0001';
      END IF;
  
      -- Map resource to field and ensure sufficient inventory
      IF p_resource NOT IN ('ore','organics','goods','energy') THEN
          RAISE EXCEPTION 'invalid_resource' USING ERRCODE='P0001';
      END IF;
      v_field := p_resource; -- matches column names
  
      -- Ensure player has enough
      IF (SELECT (CASE p_resource WHEN 'ore' THEN i.ore WHEN 'organics' THEN i.organics WHEN 'goods' THEN i.goods ELSE i.energy END)
          FROM inventories i WHERE i.player_id = v_player_id) < p_qty THEN
          RAISE EXCEPTION 'insufficient_inventory' USING ERRCODE='P0001';
      END IF;
  
      -- Move goods: decrement player inventory, increment planet stock
      EXECUTE format('UPDATE inventories SET %I = %I - $1 WHERE player_id = $2', v_field, v_field) USING p_qty, v_player_id;
      EXECUTE format('UPDATE planets SET %I = %I + $1 WHERE id = $2', v_field, v_field) USING p_qty, p_planet;
  
      RETURN (
          SELECT json_build_object(
              'player_inventory', json_build_object('ore', i.ore, 'organics', i.organics, 'goods', i.goods, 'energy', i.energy),
              'planet', json_build_object('id', pl.id, 'name', pl.name, 'ore', pl.ore, 'organics', pl.organics, 'goods', pl.goods, 'energy', pl.energy)
          )
          FROM inventories i CROSS JOIN planets pl
          WHERE i.player_id = v_player_id AND pl.id = p_planet
      );
  END;
  $_$;
  
  
  ALTER FUNCTION "public"."game_planet_store"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_planet_withdraw"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $_$
  DECLARE
      v_player_id UUID;
      v_field TEXT;
  BEGIN
      IF p_qty IS NULL OR p_qty <= 0 THEN
          RAISE EXCEPTION 'invalid_qty' USING ERRCODE = 'P0001';
      END IF;
  
      SELECT id INTO v_player_id FROM players WHERE user_id = p_user_id;
      IF v_player_id IS NULL THEN RAISE EXCEPTION 'player_not_found' USING ERRCODE='P0001'; END IF;
  
      -- Ownership
      IF NOT EXISTS (SELECT 1 FROM planets WHERE id = p_planet AND owner_player_id = v_player_id) THEN
          RAISE EXCEPTION 'not_owner' USING ERRCODE='P0001';
      END IF;
  
      IF p_resource NOT IN ('ore','organics','goods','energy') THEN
          RAISE EXCEPTION 'invalid_resource' USING ERRCODE='P0001';
      END IF;
      v_field := p_resource;
  
      -- Ensure planet has enough
      IF (SELECT (CASE p_resource WHEN 'ore' THEN pl.ore WHEN 'organics' THEN pl.organics WHEN 'goods' THEN pl.goods ELSE pl.energy END)
          FROM planets pl WHERE pl.id = p_planet) < p_qty THEN
          RAISE EXCEPTION 'insufficient_planet_stock' USING ERRCODE='P0001';
      END IF;
  
      -- Move goods back to player
      EXECUTE format('UPDATE planets SET %I = %I - $1 WHERE id = $2', v_field, v_field) USING p_qty, p_planet;
      EXECUTE format('UPDATE inventories SET %I = %I + $1 WHERE player_id = $2', v_field, v_field) USING p_qty, v_player_id;
  
      RETURN (
          SELECT json_build_object(
              'player_inventory', json_build_object('ore', i.ore, 'organics', i.organics, 'goods', i.goods, 'energy', i.energy),
              'planet', json_build_object('id', pl.id, 'name', pl.name, 'ore', pl.ore, 'organics', pl.organics, 'goods', pl.goods, 'energy', pl.energy)
          )
          FROM inventories i CROSS JOIN planets pl
          WHERE i.player_id = v_player_id AND pl.id = p_planet
      );
  END;
  $_$;
  
  
  ALTER FUNCTION "public"."game_planet_withdraw"("p_user_id" "uuid", "p_planet" "uuid", "p_resource" "text", "p_qty" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_repair"("p_user_id" "uuid", "p_hull" integer) RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
      v_player_id UUID;
      v_player_credits BIGINT;
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
      
      -- Get player info (including current sector)
      SELECT p.id, p.credits, p.current_sector
      INTO v_player_id, v_player_credits, v_current_sector
      FROM players p
      WHERE p.user_id = p_user_id;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', 'Player not found');
      END IF;
      
      -- Get ship info
      SELECT s.id, s.hull
      INTO v_ship_id, v_current_hull
      FROM ships s
      WHERE s.player_id = v_player_id;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', 'Ship not found');
      END IF;
      
      -- Calculate actual repair (capped at max hull)
      v_actual_repair := LEAST(p_hull, v_hull_max - v_current_hull);
      
      IF v_actual_repair <= 0 THEN
          RETURN json_build_object('error', 'Hull is already at maximum');
      END IF;
      
      v_total_cost := v_actual_repair * v_hull_repair_cost;
      
      -- Check if player has enough credits
      IF v_player_credits < v_total_cost THEN
          RETURN json_build_object('error', 'Insufficient credits');
      END IF;
      
      -- Perform the repair
      UPDATE ships SET hull = hull + v_actual_repair WHERE id = v_ship_id;
      UPDATE players SET credits = credits - v_total_cost WHERE id = v_player_id;
      
      -- Log the repair as an audit row (resource label 'hull_repair') if a port exists here
      SELECT id INTO v_port_id
      FROM ports
      WHERE sector_id = v_current_sector;
  
      IF FOUND THEN
          INSERT INTO trades (player_id, port_id, action, resource, qty, price)
          VALUES (v_player_id, v_port_id, 'buy', 'hull_repair', v_actual_repair, v_hull_repair_cost);
      END IF;
  
      -- Get updated values
      SELECT hull INTO v_current_hull FROM ships WHERE id = v_ship_id;
      SELECT credits INTO v_player_credits FROM players WHERE id = v_player_id;
      
      -- Return success
      RETURN json_build_object(
          'ok', true,
          'credits', v_player_credits,
          'ship', json_build_object(
              'hull', v_current_hull
          )
      );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."game_repair"("p_user_id" "uuid", "p_hull" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_ship_rename"("p_user_id" "uuid", "p_name" "text") RETURNS "jsonb"
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
  
  
> CREATE OR REPLACE FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text") RETURNS "jsonb"
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_player players%ROWTYPE;
    v_ship ships%ROWTYPE;
    v_cost integer;
  BEGIN
    -- Get player data
    SELECT * INTO v_player FROM players WHERE user_id = p_user_id;
    
    IF NOT FOUND THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'player_not_found', 'message', 'Player not found'));
    END IF;
  
    -- Get ship data
    SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;
    
    IF NOT FOUND THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'ship_not_found', 'message', 'Ship not found'));
    END IF;
  
    -- Check if player is at a special port
    PERFORM 1 FROM ports p
    JOIN sectors s ON p.sector_id = s.id
    WHERE sector_id = v_player.current_sector AND kind = 'special';
  
    IF NOT FOUND THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'port_not_special', 'message', 'Upgrades are only available at Special ports.'));
    END IF;
  
    -- Validate attribute
    IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull') THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
    END IF;
  
    -- Calculate cost based on attribute
    CASE p_attr
      WHEN 'engine' THEN
        v_cost := 500 * (v_ship.engine_lvl + 1);
      WHEN 'computer' THEN
        v_cost := 400 * (v_ship.comp_lvl + 1);
      WHEN 'sensors' THEN
        v_cost := 400 * (v_ship.sensor_lvl + 1);
      WHEN 'shields' THEN
        v_cost := 300 * (v_ship.shield_lvl + 1);
      WHEN 'hull' THEN
        v_cost := 2000 * (v_ship.hull_lvl + 1);
    END CASE;
  
    -- Check if player has enough credits
    IF v_player.credits < v_cost THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Insufficient credits for upgrade'));
    END IF;
  
    -- Apply upgrade
    CASE p_attr
      WHEN 'engine' THEN
        UPDATE ships SET engine_lvl = engine_lvl + 1 WHERE player_id = v_player.id;
      WHEN 'computer' THEN
        UPDATE ships SET comp_lvl = comp_lvl + 1 WHERE player_id = v_player.id;
      WHEN 'sensors' THEN
        UPDATE ships SET sensor_lvl = sensor_lvl + 1 WHERE player_id = v_player.id;
      WHEN 'shields' THEN
        UPDATE ships SET shield_lvl = shield_lvl + 1 WHERE player_id = v_player.id;
        UPDATE ships SET shield = shield_max WHERE player_id = v_player.id;
      WHEN 'hull' THEN
        UPDATE ships SET 
          hull_lvl = hull_lvl + 1,
          hull = hull_max,
          cargo = CASE 
            WHEN hull_lvl + 1 = 1 THEN 1000
            WHEN hull_lvl + 1 = 2 THEN 3500
            WHEN hull_lvl + 1 = 3 THEN 7224
            WHEN hull_lvl + 1 = 4 THEN 10000
            WHEN hull_lvl + 1 = 5 THEN 13162
            ELSE FLOOR(1000 * POWER(hull_lvl + 1, 1.8))
          END
        WHERE player_id = v_player.id;
    END CASE;
  
    -- Deduct credits
    UPDATE players SET credits = credits - v_cost WHERE id = v_player.id;
  
    -- Get updated ship data
    SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;
    SELECT * INTO v_player FROM players WHERE id = v_player.id;
  
    -- Return success with updated data
    RETURN jsonb_build_object(
      'ok', true,
      'credits', v_player.credits,
      'ship', jsonb_build_object(
        'name', v_ship.name,
        'hull', v_ship.hull,
        'hull_max', v_ship.hull_max,
        'hull_lvl', v_ship.hull_lvl,
        'shield', v_ship.shield,
        'shield_max', v_ship.shield_max,
        'shield_lvl', v_ship.shield_lvl,
        'engine_lvl', v_ship.engine_lvl,
        'comp_lvl', v_ship.comp_lvl,
        'sensor_lvl', v_ship.sensor_lvl,
        'cargo', v_ship.cargo,
        'fighters', v_ship.fighters,
        'torpedoes', v_ship.torpedoes
      )
    );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_cost INTEGER;
    v_result JSONB;
  BEGIN
    -- Validate attribute
    IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull') THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
    END IF;
  
    -- Get player data - filter by universe if provided
    IF p_universe_id IS NOT NULL THEN
      SELECT p.* INTO v_player
      FROM players p
      WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id
      FOR UPDATE;
    ELSE
      SELECT p.* INTO v_player
      FROM players p
      WHERE p.user_id = p_user_id
      FOR UPDATE;
    END IF;
  
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
  
    -- Check if player is at a Special port
    IF NOT EXISTS (
      SELECT 1 FROM ports p 
      JOIN sectors s ON p.sector_id = s.id 
      WHERE s.id = v_player.current_sector AND p.kind = 'special'
    ) THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'wrong_port', 'message', 'Must be at a Special port to upgrade'));
    END IF;
  
    -- Calculate cost
    CASE p_attr
      WHEN 'engine' THEN v_cost := 500 * (v_ship.engine_lvl + 1);
      WHEN 'computer' THEN v_cost := 1000 * (v_ship.comp_lvl + 1);
      WHEN 'sensors' THEN v_cost := 800 * (v_ship.sensor_lvl + 1);
      WHEN 'shields' THEN v_cost := 1500 * (v_ship.shield_lvl + 1);
      WHEN 'hull' THEN v_cost := 2000 * (v_ship.hull_lvl + 1);
    END CASE;
  
    -- Check if player has enough credits
    IF v_player.credits < v_cost THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
    END IF;
  
    -- Perform upgrade
    CASE p_attr
      WHEN 'engine' THEN
        UPDATE ships SET engine_lvl = engine_lvl + 1 WHERE player_id = v_player.id;
      WHEN 'computer' THEN
        UPDATE ships SET comp_lvl = comp_lvl + 1 WHERE player_id = v_player.id;
      WHEN 'sensors' THEN
        UPDATE ships SET sensor_lvl = sensor_lvl + 1 WHERE player_id = v_player.id;
      WHEN 'shields' THEN
        UPDATE ships SET 
          shield_lvl = shield_lvl + 1,
          shield = shield_max
        WHERE player_id = v_player.id;
      WHEN 'hull' THEN
        UPDATE ships SET 
          hull_lvl = hull_lvl + 1,
          hull = hull_max,
          cargo = CASE 
            WHEN hull_lvl + 1 = 1 THEN 1000
            WHEN hull_lvl + 1 = 2 THEN 3500
            WHEN hull_lvl + 1 = 3 THEN 7224
            WHEN hull_lvl + 1 = 4 THEN 10000
            WHEN hull_lvl + 1 = 5 THEN 13162
            ELSE FLOOR(1000 * POWER(hull_lvl + 1, 1.8))
          END
        WHERE player_id = v_player.id;
    END CASE;
  
    -- Deduct credits
    UPDATE players SET credits = credits - v_cost WHERE id = v_player.id;
  
    RETURN jsonb_build_object(
      'ok', true,
      'attribute', p_attr,
      'cost', v_cost,
      'credits_after', v_player.credits - v_cost
    );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."game_ship_upgrade"("p_user_id" "uuid", "p_attr" "text", "p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_trade"("p_user_id" "uuid", "p_port_id" "uuid", "p_action" "text", "p_resource" "text", "p_qty" integer) RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_player_id UUID;
    v_player_credits BIGINT;
    v_player_current_sector UUID;
    v_ship RECORD;
    v_port RECORD;
    v_inventory RECORD;
    v_unit_price NUMERIC;
    v_total NUMERIC;
    v_result JSON;
    v_cargo_used INTEGER;
    v_cargo_free INTEGER;
  BEGIN
    IF p_action NOT IN ('buy','sell') THEN
      RETURN json_build_object('error', json_build_object('code','invalid_action','message','Invalid action'));
    END IF;
    IF p_resource NOT IN ('ore','organics','goods','energy') THEN
      RETURN json_build_object('error', json_build_object('code','invalid_resource','message','Invalid resource'));
    END IF;
    IF p_qty <= 0 THEN
      RETURN json_build_object('error', json_build_object('code','invalid_qty','message','Quantity must be positive'));
    END IF;
  
    SELECT p.id, p.credits, p.current_sector
    INTO v_player_id, v_player_credits, v_player_current_sector
    FROM players p WHERE p.user_id = p_user_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
    END IF;
  
    SELECT * INTO v_ship FROM ships WHERE player_id = v_player_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
    END IF;
  
    SELECT * INTO v_port FROM ports WHERE id = p_port_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Port not found'));
    END IF;
    IF v_port.sector_id != v_player_current_sector THEN
      RETURN json_build_object('error', json_build_object('code','wrong_sector','message','Player not in port sector'));
    END IF;
  
    IF v_port.kind = 'special' THEN
      RETURN json_build_object('error', json_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.'));
    END IF;
  
    SELECT * INTO v_inventory FROM inventories WHERE player_id = v_player_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Inventory not found'));
    END IF;
  
    -- Compute unit price using base price and dynamic stock-based multiplier
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
      
      -- Apply dynamic pricing based on stock levels
      price_multiplier := calculate_price_multiplier(stock_level);
      v_unit_price := base_price * price_multiplier;
    END;
  
    IF p_action = 'buy' THEN
      -- For buy: port must SELL the resource if it's its kind; otherwise only BUY other resources (reject)
      IF p_resource = v_port.kind THEN
        v_unit_price := v_unit_price * 0.90; -- sell price (player buys)
        -- Check stock
        IF (p_resource='ore' AND v_port.ore < p_qty) OR
           (p_resource='organics' AND v_port.organics < p_qty) OR
           (p_resource='goods' AND v_port.goods < p_qty) OR
           (p_resource='energy' AND v_port.energy < p_qty) THEN
          RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Insufficient port stock'));
        END IF;
      ELSE
        RETURN json_build_object('error', json_build_object('code','resource_not_allowed','message', 'Can only buy the port''s native commodity'));
      END IF;
  
      v_total := v_unit_price * p_qty;
      IF v_player_credits < v_total THEN
        RETURN json_build_object('error', json_build_object('code','insufficient_credits','message','Insufficient credits'));
      END IF;
  
      -- Cargo capacity check: qty <= cargo_free
      v_cargo_used := v_inventory.ore + v_inventory.organics + v_inventory.goods + v_inventory.energy;
      v_cargo_free := GREATEST(v_ship.cargo - v_cargo_used, 0);
      IF p_qty > v_cargo_free THEN
        RETURN json_build_object('error', json_build_object('code','insufficient_cargo','message','Insufficient cargo capacity'));
      END IF;
  
      UPDATE players SET credits = credits - v_total WHERE id = v_player_id;
      UPDATE inventories SET 
        ore = ore + CASE WHEN p_resource='ore' THEN p_qty ELSE 0 END,
        organics = organics + CASE WHEN p_resource='organics' THEN p_qty ELSE 0 END,
        goods = goods + CASE WHEN p_resource='goods' THEN p_qty ELSE 0 END,
        energy = energy + CASE WHEN p_resource='energy' THEN p_qty ELSE 0 END
      WHERE player_id = v_player_id;
      UPDATE ports SET 
        ore = ore - CASE WHEN p_resource='ore' THEN p_qty ELSE 0 END,
        organics = organics - CASE WHEN p_resource='organics' THEN p_qty ELSE 0 END,
        goods = goods - CASE WHEN p_resource='goods' THEN p_qty ELSE 0 END,
        energy = energy - CASE WHEN p_resource='energy' THEN p_qty ELSE 0 END
      WHERE id = p_port_id;
  
    ELSIF p_action = 'sell' THEN
      -- For sell: port must BUY resource (any resource except its kind)
      IF p_resource = v_port.kind THEN
        RETURN json_build_object('error', json_build_object('code','resource_not_allowed','message', 'Cannot sell the port''s native commodity here'));
      END IF;
      v_unit_price := v_unit_price * 1.10; -- buy price (player sells to port)
  
      -- Check player inventory
      IF (p_resource='ore' AND v_inventory.ore < p_qty) OR
         (p_resource='organics' AND v_inventory.organics < p_qty) OR
         (p_resource='goods' AND v_inventory.goods < p_qty) OR
         (p_resource='energy' AND v_inventory.energy < p_qty) THEN
        RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Insufficient inventory'));
      END IF;
  
      v_total := v_unit_price * p_qty;
      UPDATE players SET credits = credits + v_total WHERE id = v_player_id;
      UPDATE inventories SET 
        ore = ore - CASE WHEN p_resource='ore' THEN p_qty ELSE 0 END,
        organics = organics - CASE WHEN p_resource='organics' THEN p_qty ELSE 0 END,
        goods = goods - CASE WHEN p_resource='goods' THEN p_qty ELSE 0 END,
        energy = energy - CASE WHEN p_resource='energy' THEN p_qty ELSE 0 END
      WHERE player_id = v_player_id;
      UPDATE ports SET 
        ore = ore + CASE WHEN p_resource='ore' THEN p_qty ELSE 0 END,
        organics = organics + CASE WHEN p_resource='organics' THEN p_qty ELSE 0 END,
        goods = goods + CASE WHEN p_resource='goods' THEN p_qty ELSE 0 END,
        energy = energy + CASE WHEN p_resource='energy' THEN p_qty ELSE 0 END
      WHERE id = p_port_id;
    END IF;
  
    -- Log trade at effective unit price for audit
    INSERT INTO trades (player_id, port_id, action, resource, qty, price)
    VALUES (v_player_id, p_port_id, p_action, p_resource, p_qty, v_unit_price);
  
    -- Return snapshot
    SELECT credits INTO v_player_credits FROM players WHERE id = v_player_id;
    SELECT * INTO v_inventory FROM inventories WHERE player_id = v_player_id;
    SELECT * INTO v_port FROM ports WHERE id = p_port_id;
  
    RETURN json_build_object(
      'ok', true,
      'player', json_build_object(
        'credits', v_player_credits,
        'inventory', json_build_object(
          'ore', v_inventory.ore,
          'organics', v_inventory.organics,
          'goods', v_inventory.goods,
          'energy', v_inventory.energy
        )
      ),
      'port', json_build_object(
        'stock', json_build_object(
          'ore', v_port.ore,
          'organics', v_port.organics,
          'goods', v_port.goods,
          'energy', v_port.energy
        ),
        'prices', json_build_object(
          'ore', v_port.price_ore,
          'organics', v_port.price_organics,
          'goods', v_port.price_goods,
          'energy', v_port.price_energy
        )
      )
    );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."game_trade"("p_user_id" "uuid", "p_port_id" "uuid", "p_action" "text", "p_resource" "text", "p_qty" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_trade"("p_user_id" "uuid", "p_port_id" "uuid", "p_action" "text", "p_resource" "text", "p_qty" integer, "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_player_id UUID;
    v_player_credits BIGINT;
    v_player_current_sector UUID;
    v_ship RECORD;
    v_port RECORD;
    v_inventory RECORD;
    v_unit_price NUMERIC;
    v_total NUMERIC;
    v_result JSON;
    v_cargo_used INTEGER;
    v_cargo_free INTEGER;
  BEGIN
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
      SELECT p.id, p.credits, p.current_sector
      INTO v_player_id, v_player_credits, v_player_current_sector
      FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
    ELSE
      SELECT p.id, p.credits, p.current_sector
      INTO v_player_id, v_player_credits, v_player_current_sector
      FROM players p WHERE p.user_id = p_user_id;
    END IF;
    
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Player not found'));
    END IF;
  
    SELECT * INTO v_ship FROM ships WHERE player_id = v_player_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Ship not found'));
    END IF;
  
    SELECT * INTO v_port FROM ports WHERE id = p_port_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Port not found'));
    END IF;
    IF v_port.sector_id != v_player_current_sector THEN
      RETURN json_build_object('error', json_build_object('code','wrong_sector','message','Player not in port sector'));
    END IF;
  
    IF v_port.kind = 'special' THEN
      RETURN json_build_object('error', json_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.'));
    END IF;
  
    -- Get inventory
    SELECT * INTO v_inventory FROM inventories WHERE player_id = v_player_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error', json_build_object('code','not_found','message','Inventory not found'));
    END IF;
  
    -- Calculate cargo usage
    v_cargo_used := COALESCE(v_inventory.ore, 0) + COALESCE(v_inventory.organics, 0) + 
                    COALESCE(v_inventory.goods, 0) + COALESCE(v_inventory.energy, 0);
    v_cargo_free := v_ship.cargo - v_cargo_used;
  
    -- Handle buy action
    IF p_action = 'buy' THEN
      -- Check if buying native commodity
      IF p_resource != v_port.kind THEN
        RETURN json_build_object('error', json_build_object('code','resource_not_allowed','message','Can only buy the port''s native commodity'));
      END IF;
      
      -- Check cargo capacity
      IF p_qty > v_cargo_free THEN
        RETURN json_build_object('error', json_build_object('code','insufficient_cargo','message','Not enough cargo space'));
      END IF;
      
      -- Calculate price (0.90 * base price for native commodity)
      CASE p_resource
        WHEN 'ore' THEN v_unit_price := v_port.price_ore * 0.90;
        WHEN 'organics' THEN v_unit_price := v_port.price_organics * 0.90;
        WHEN 'goods' THEN v_unit_price := v_port.price_goods * 0.90;
        WHEN 'energy' THEN v_unit_price := v_port.price_energy * 0.90;
      END CASE;
      
      v_total := v_unit_price * p_qty;
      
      -- Check credits
      IF v_total > v_player_credits THEN
        RETURN json_build_object('error', json_build_object('code','insufficient_credits','message','Not enough credits'));
      END IF;
      
      -- Check port stock
      CASE p_resource
        WHEN 'ore' THEN 
          IF p_qty > v_port.ore THEN
            RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Not enough stock'));
          END IF;
        WHEN 'organics' THEN 
          IF p_qty > v_port.organics THEN
            RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Not enough stock'));
          END IF;
        WHEN 'goods' THEN 
          IF p_qty > v_port.goods THEN
            RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Not enough stock'));
          END IF;
        WHEN 'energy' THEN 
          IF p_qty > v_port.energy THEN
            RETURN json_build_object('error', json_build_object('code','insufficient_stock','message','Not enough stock'));
          END IF;
      END CASE;
      
      -- Execute buy transaction
      UPDATE players SET credits = credits - v_total WHERE id = v_player_id;
      
      CASE p_resource
        WHEN 'ore' THEN 
          UPDATE inventories SET ore = ore + p_qty WHERE player_id = v_player_id;
          UPDATE ports SET ore = ore - p_qty WHERE id = p_port_id;
        WHEN 'organics' THEN 
          UPDATE inventories SET organics = organics + p_qty WHERE player_id = v_player_id;
          UPDATE ports SET organics = organics - p_qty WHERE id = p_port_id;
        WHEN 'goods' THEN 
          UPDATE inventories SET goods = goods + p_qty WHERE player_id = v_player_id;
          UPDATE ports SET goods = goods - p_qty WHERE id = p_port_id;
        WHEN 'energy' THEN 
          UPDATE inventories SET energy = energy + p_qty WHERE player_id = v_player_id;
          UPDATE ports SET energy = energy - p_qty WHERE id = p_port_id;
      END CASE;
      
      -- Log trade
      INSERT INTO trades (player_id, port_id, action, resource, quantity, unit_price, total_price)
      VALUES (v_player_id, p_port_id, 'buy', p_resource, p_qty, v_unit_price, v_total);
      
      RETURN json_build_object(
        'ok', true,
        'action', 'buy',
        'resource', p_resource,
        'quantity', p_qty,
        'unit_price', v_unit_price,
        'total_price', v_total,
        'credits_after', v_player_credits - v_total
      );
    END IF;
  
    -- Handle sell action
    IF p_action = 'sell' THEN
      -- Check if selling non-native commodity
      IF p_resource = v_port.kind THEN
        RETURN json_build_object('error', json_build_object('code','resource_not_allowed','message','Cannot sell the port''s native commodity here'));
      END IF;
      
      -- Check inventory
      CASE p_resource
        WHEN 'ore' THEN 
          IF p_qty > COALESCE(v_inventory.ore, 0) THEN
            RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Not enough inventory'));
          END IF;
        WHEN 'organics' THEN 
          IF p_qty > COALESCE(v_inventory.organics, 0) THEN
            RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Not enough inventory'));
          END IF;
        WHEN 'goods' THEN 
          IF p_qty > COALESCE(v_inventory.goods, 0) THEN
            RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Not enough inventory'));
          END IF;
        WHEN 'energy' THEN 
          IF p_qty > COALESCE(v_inventory.energy, 0) THEN
            RETURN json_build_object('error', json_build_object('code','insufficient_inventory','message','Not enough inventory'));
          END IF;
      END CASE;
      
      -- Calculate price (1.10 * base price for non-native commodity)
      CASE p_resource
        WHEN 'ore' THEN v_unit_price := v_port.price_ore * 1.10;
        WHEN 'organics' THEN v_unit_price := v_port.price_organics * 1.10;
        WHEN 'goods' THEN v_unit_price := v_port.price_goods * 1.10;
        WHEN 'energy' THEN v_unit_price := v_port.price_energy * 1.10;
      END CASE;
      
      v_total := v_unit_price * p_qty;
      
      -- Execute sell transaction
      UPDATE players SET credits = credits + v_total WHERE id = v_player_id;
      
      CASE p_resource
        WHEN 'ore' THEN 
          UPDATE inventories SET ore = ore - p_qty WHERE player_id = v_player_id;
          UPDATE ports SET ore = ore + p_qty WHERE id = p_port_id;
        WHEN 'organics' THEN 
          UPDATE inventories SET organics = organics - p_qty WHERE player_id = v_player_id;
          UPDATE ports SET organics = organics + p_qty WHERE id = p_port_id;
        WHEN 'goods' THEN 
          UPDATE inventories SET goods = goods - p_qty WHERE player_id = v_player_id;
          UPDATE ports SET goods = goods + p_qty WHERE id = p_port_id;
        WHEN 'energy' THEN 
          UPDATE inventories SET energy = energy - p_qty WHERE player_id = v_player_id;
> CREATE OR REPLACE FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid") RETURNS "jsonb"
      LANGUAGE "plpgsql"
      AS $$
  declare
    v_player record;
    v_ship record;
    v_port record;
    v_inv record;
    pc text; -- port commodity
    sell_price numeric; -- native sell price (0.90 * base)
    buy_prices jsonb;   -- other resources buy price (1.10 * base)
    proceeds numeric := 0;
    sold_ore int := 0; sold_organics int := 0; sold_goods int := 0; sold_energy int := 0;
    new_ore int; new_organics int; new_goods int; new_energy int;
    native_stock int; native_price numeric;
    credits_after numeric;
    capacity int; cargo_used int; cargo_after int; q int := 0;
    native_key text;
    err jsonb;
  begin
    -- Load player, ship, port
    select * into v_player from public.players where user_id = p_user_id for update;
    if not found then return jsonb_build_object('error', jsonb_build_object('code','not_found','message','Player not found')); end if;
  
    select * into v_ship from public.ships where player_id = v_player.id for update;
    if not found then return jsonb_build_object('error', jsonb_build_object('code','not_found','message','Ship not found')); end if;
  
    select p.*, s.number as sector_number into v_port
    from public.ports p
    join public.sectors s on s.id = p.sector_id
    where p.id = p_port for update;
    if not found then return jsonb_build_object('error', jsonb_build_object('code','not_found','message','Port not found')); end if;
    if v_port.kind = 'special' then return jsonb_build_object('error', jsonb_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.')); end if;
  
    -- Validate co-location
    if v_player.current_sector <> v_port.sector_id then
      return jsonb_build_object('error', jsonb_build_object('code','wrong_sector','message','Player not in port sector'));
    end if;
  
    pc := v_port.kind; -- ore|organics|goods|energy
    native_key := pc;
  
    -- pricing with dynamic stock-based multipliers
    native_price := case pc
      when 'ore' then v_port.price_ore * calculate_price_multiplier(v_port.ore)
      when 'organics' then v_port.price_organics * calculate_price_multiplier(v_port.organics)
      when 'goods' then v_port.price_goods * calculate_price_multiplier(v_port.goods)
      when 'energy' then v_port.price_energy * calculate_price_multiplier(v_port.energy)
    end;
    sell_price := native_price * 0.90; -- player buys from port at 0.90 * dynamic price
  
    -- compute proceeds from selling all non-native at 1.10 * dynamic price
    select * into v_inv from public.inventories where player_id = v_player.id for update;
    if not found then return jsonb_build_object('error', jsonb_build_object('code','not_found','message','Inventory not found')); end if;
    new_ore := v_inv.ore;
    new_organics := v_inv.organics;
    new_goods := v_inv.goods;
    new_energy := v_inv.energy;
  
    -- sell non-native resources with dynamic pricing
    if pc <> 'ore' and v_inv.ore > 0 then
      proceeds := proceeds + (v_port.price_ore * calculate_price_multiplier(v_port.ore) * 1.10) * v_inv.ore;
      sold_ore := v_inv.ore;
      new_ore := 0;
      v_port.ore := v_port.ore + sold_ore;
    end if;
    if pc <> 'organics' and v_inv.organics > 0 then
      proceeds := proceeds + (v_port.price_organics * calculate_price_multiplier(v_port.organics) * 1.10) * v_inv.organics;
      sold_organics := v_inv.organics;
      new_organics := 0;
      v_port.organics := v_port.organics + sold_organics;
    end if;
    if pc <> 'goods' and v_inv.goods > 0 then
      proceeds := proceeds + (v_port.price_goods * calculate_price_multiplier(v_port.goods) * 1.10) * v_inv.goods;
      sold_goods := v_inv.goods;
      new_goods := 0;
      v_port.goods := v_port.goods + sold_goods;
    end if;
    if pc <> 'energy' and v_inv.energy > 0 then
      proceeds := proceeds + (v_port.price_energy * calculate_price_multiplier(v_port.energy) * 1.10) * v_inv.energy;
      sold_energy := v_inv.energy;
      new_energy := 0;
      v_port.energy := v_port.energy + sold_energy;
    end if;
  
    -- credits and capacity after sells
    credits_after := v_player.credits + proceeds;
    cargo_used := new_ore + new_organics + new_goods + new_energy;
    capacity := v_ship.cargo - cargo_used;
  
    -- native stock and buy quantity
    native_stock := case pc
      when 'ore' then v_port.ore
      when 'organics' then v_port.organics
      when 'goods' then v_port.goods
      when 'energy' then v_port.energy
    end;
  
    q := least(native_stock, floor(credits_after / sell_price)::int, greatest(capacity,0));
    if q < 0 then q := 0; end if;
  
    -- apply buy
    if q > 0 then
      credits_after := credits_after - (q * sell_price);
      case pc
        when 'ore' then begin new_ore := new_ore + q; v_port.ore := v_port.ore - q; end;
        when 'organics' then begin new_organics := new_organics + q; v_port.organics := v_port.organics - q; end;
        when 'goods' then begin new_goods := new_goods + q; v_port.goods := v_port.goods - q; end;
        when 'energy' then begin new_energy := new_energy + q; v_port.energy := v_port.energy - q; end;
      end case;
    end if;
  
    -- persist changes
    update public.players
    set credits = credits_after
    where id = v_player.id;
  
    update public.inventories
    set ore = new_ore,
        organics = new_organics,
        goods = new_goods,
        energy = new_energy
    where player_id = v_player.id;
  
    update public.ports set
      ore = v_port.ore,
      organics = v_port.organics,
      goods = v_port.goods,
      energy = v_port.energy
    where id = p_port;
  
    return jsonb_build_object(
      'sold', jsonb_build_object('ore', sold_ore, 'organics', sold_organics, 'goods', sold_goods, 'energy', sold_energy),
      'bought', jsonb_build_object('resource', pc, 'qty', q),
      'credits', credits_after,
      'inventory_after', jsonb_build_object('ore', new_ore, 'organics', new_organics, 'goods', new_goods, 'energy', new_energy),
      'port_stock_after', jsonb_build_object('ore', v_port.ore, 'organics', v_port.organics, 'goods', v_port.goods, 'energy', v_port.energy),
      'prices', jsonb_build_object('pcSell', sell_price)
    );
  end;
  $$;
  
  
  ALTER FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
      LANGUAGE "plpgsql"
      AS $$
  DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_port RECORD;
    v_inv RECORD;
    pc TEXT; -- port commodity
    sell_price NUMERIC; -- native sell price (0.90 * base)
    buy_prices JSONB;   -- other resources buy price (1.10 * base)
    proceeds NUMERIC := 0;
    sold_ore INT := 0; sold_organics INT := 0; sold_goods INT := 0; sold_energy INT := 0;
    new_ore INT; new_organics INT; new_goods INT; new_energy INT;
    native_stock INT; native_price NUMERIC;
    credits_after NUMERIC;
    capacity INT; cargo_used INT; cargo_after INT; q INT := 0;
    native_key TEXT;
    err JSONB;
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
  
    -- Get inventory
    SELECT * INTO v_inv FROM public.inventories WHERE player_id = v_player.id FOR UPDATE;
    IF NOT FOUND THEN 
      RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Inventory not found')); 
    END IF;
  
    -- Calculate cargo capacity
    capacity := v_ship.cargo;
    cargo_used := COALESCE(v_inv.ore, 0) + COALESCE(v_inv.organics, 0) + COALESCE(v_inv.goods, 0) + COALESCE(v_inv.energy, 0);
    
    -- Auto-sell all non-native resources
    IF pc != 'ore' AND COALESCE(v_inv.ore, 0) > 0 THEN
      sold_ore := v_inv.ore;
      proceeds := proceeds + (sold_ore * v_port.price_ore * 1.10);
      UPDATE public.inventories SET ore = 0 WHERE player_id = v_player.id;
      UPDATE public.ports SET ore = ore + sold_ore WHERE id = p_port;
    END IF;
    
    IF pc != 'organics' AND COALESCE(v_inv.organics, 0) > 0 THEN
      sold_organics := v_inv.organics;
      proceeds := proceeds + (sold_organics * v_port.price_organics * 1.10);
      UPDATE public.inventories SET organics = 0 WHERE player_id = v_player.id;
      UPDATE public.ports SET organics = organics + sold_organics WHERE id = p_port;
    END IF;
    
    IF pc != 'goods' AND COALESCE(v_inv.goods, 0) > 0 THEN
      sold_goods := v_inv.goods;
      proceeds := proceeds + (sold_goods * v_port.price_goods * 1.10);
      UPDATE public.inventories SET goods = 0 WHERE player_id = v_player.id;
      UPDATE public.ports SET goods = goods + sold_goods WHERE id = p_port;
    END IF;
    
    IF pc != 'energy' AND COALESCE(v_inv.energy, 0) > 0 THEN
      sold_energy := v_inv.energy;
      proceeds := proceeds + (sold_energy * v_port.price_energy * 1.10);
      UPDATE public.inventories SET energy = 0 WHERE player_id = v_player.id;
      UPDATE public.ports SET energy = energy + sold_energy WHERE id = p_port;
    END IF;
  
    -- Update player credits
    UPDATE public.players SET credits = credits + proceeds WHERE id = v_player.id;
    credits_after := v_player.credits + proceeds;
  
    -- Calculate cargo free after sells
    cargo_after := capacity - 0; -- All inventory sold
  
    -- Auto-buy native commodity
    CASE pc
      WHEN 'ore' THEN 
        native_price := v_port.price_ore * 0.90;
        native_stock := v_port.ore;
      WHEN 'organics' THEN 
        native_price := v_port.price_organics * 0.90;
        native_stock := v_port.organics;
      WHEN 'goods' THEN 
        native_price := v_port.price_goods * 0.90;
        native_stock := v_port.goods;
      WHEN 'energy' THEN 
        native_price := v_port.price_energy * 0.90;
        native_stock := v_port.energy;
    END CASE;
  
    q := LEAST(native_stock, FLOOR(credits_after / native_price), cargo_after);
    
    IF q > 0 THEN
      CASE pc
        WHEN 'ore' THEN 
          UPDATE public.inventories SET ore = ore + q WHERE player_id = v_player.id;
          UPDATE public.ports SET ore = ore - q WHERE id = p_port;
        WHEN 'organics' THEN 
          UPDATE public.inventories SET organics = organics + q WHERE player_id = v_player.id;
          UPDATE public.ports SET organics = organics - q WHERE id = p_port;
        WHEN 'goods' THEN 
          UPDATE public.inventories SET goods = goods + q WHERE player_id = v_player.id;
          UPDATE public.ports SET goods = goods - q WHERE id = p_port;
        WHEN 'energy' THEN 
          UPDATE public.inventories SET energy = energy + q WHERE player_id = v_player.id;
          UPDATE public.ports SET energy = energy - q WHERE id = p_port;
      END CASE;
      
      UPDATE public.players SET credits = credits - (q * native_price) WHERE id = v_player.id;
    END IF;
  
    -- Get final inventory
    SELECT ore, organics, goods, energy INTO new_ore, new_organics, new_goods, new_energy
    FROM public.inventories WHERE player_id = v_player.id;
  
    RETURN jsonb_build_object(
      'ok', true,
      'sold', jsonb_build_object(
        'ore', sold_ore,
        'organics', sold_organics,
        'goods', sold_goods,
        'energy', sold_energy
      ),
      'bought', jsonb_build_object(
        'resource', pc,
        'qty', q
      ),
      'credits_after', credits_after - (q * native_price),
      'inventory_after', jsonb_build_object(
        'ore', new_ore,
        'organics', new_organics,
        'goods', new_goods,
        'energy', new_energy
      )
    );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid", "p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."game_upgrade"("p_user_id" "uuid", "p_item" "text", "p_qty" integer) RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
      v_player_id UUID;
      v_player_credits BIGINT;
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
      
      -- Get player info (including current sector)
      SELECT p.id, p.credits, p.current_sector
      INTO v_player_id, v_player_credits, v_current_sector
      FROM players p
      WHERE p.user_id = p_user_id;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', 'Player not found');
      END IF;
  
      -- Ensure there is a port in the player's current sector
      SELECT id INTO v_port_id
      FROM ports
      WHERE sector_id = v_current_sector;
  
      IF NOT FOUND THEN
          RETURN json_build_object('error', 'No port in current sector');
      END IF;
      
      -- Get ship info
      SELECT s.id, s.fighters, s.torpedoes
      INTO v_ship_id, v_fighters, v_torpedoes
      FROM ships s
      WHERE s.player_id = v_player_id;
      
      IF NOT FOUND THEN
          RETURN json_build_object('error', 'Ship not found');
      END IF;
      
      -- Set unit cost based on item
      CASE p_item
          WHEN 'fighters' THEN v_unit_cost := 50;
          WHEN 'torpedoes' THEN v_unit_cost := 120;
      END CASE;
      
      v_total_cost := v_unit_cost * p_qty;
      
      -- Check if player has enough credits
      IF v_player_credits < v_total_cost THEN
          RETURN json_build_object('error', 'Insufficient credits');
      END IF;
      
      -- Perform the upgrade
      IF p_item = 'fighters' THEN
          UPDATE ships SET fighters = fighters + p_qty WHERE id = v_ship_id;
          UPDATE players SET credits = credits - v_total_cost WHERE id = v_player_id;
          
          -- Log the purchase (audit)
          INSERT INTO trades (player_id, port_id, action, resource, qty, price)
          VALUES (v_player_id, v_port_id, 'buy', 'fighters', p_qty, v_unit_cost);
          
          -- Get updated values
          SELECT fighters INTO v_fighters FROM ships WHERE id = v_ship_id;
          SELECT credits INTO v_player_credits FROM players WHERE id = v_player_id;
          
      ELSIF p_item = 'torpedoes' THEN
          UPDATE ships SET torpedoes = torpedoes + p_qty WHERE id = v_ship_id;
          UPDATE players SET credits = credits - v_total_cost WHERE id = v_player_id;
          
          -- Log the purchase (audit)
          INSERT INTO trades (player_id, port_id, action, resource, qty, price)
          VALUES (v_player_id, v_port_id, 'buy', 'torpedoes', p_qty, v_unit_cost);
          
          -- Get updated values
          SELECT torpedoes INTO v_torpedoes FROM ships WHERE id = v_ship_id;
          SELECT credits INTO v_player_credits FROM players WHERE id = v_player_id;
      END IF;
      
      -- Return success
      RETURN json_build_object(
          'ok', true,
          'credits', v_player_credits,
          'ship', json_build_object(
              'fighters', v_fighters,
              'torpedoes', v_torpedoes
          )
      );
  END;
  $$;
  
  
  ALTER FUNCTION "public"."game_upgrade"("p_user_id" "uuid", "p_item" "text", "p_qty" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."get_leaderboard"("p_universe_id" "uuid", "p_limit" integer DEFAULT 50) RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_result JSONB := '[]'::jsonb;
    v_player RECORD;
    v_ai RECORD;
  BEGIN
    -- Get top players
    FOR v_player IN 
      SELECT 
        pr.rank_position,
        p.handle,
        pr.total_score,
        pr.economic_score,
        pr.territorial_score,
        pr.military_score,
        pr.exploration_score,
        'player' as type
      FROM player_rankings pr
      JOIN players p ON pr.player_id = p.id
      WHERE pr.universe_id = p_universe_id
      ORDER BY pr.rank_position
      LIMIT p_limit
    LOOP
      v_result := v_result || jsonb_build_object(
        'rank', v_player.rank_position,
        'name', v_player.handle,
        'total_score', v_player.total_score,
        'economic_score', v_player.economic_score,
        'territorial_score', v_player.territorial_score,
        'military_score', v_player.military_score,
        'exploration_score', v_player.exploration_score,
        'type', v_player.type
      );
    END LOOP;
    
    -- Get AI players
    FOR v_ai IN 
      SELECT 
        ap.rank_position,
        ap.name,
        ap.total_score,
        ap.economic_score,
        ap.territorial_score,
        ap.military_score,
        ap.exploration_score,
        'ai' as type
      FROM ai_players ap
      WHERE ap.universe_id = p_universe_id
      ORDER BY ap.rank_position
    LOOP
      v_result := v_result || jsonb_build_object(
        'rank', v_ai.rank_position,
        'name', v_ai.name,
        'total_score', v_ai.total_score,
        'economic_score', v_ai.economic_score,
        'territorial_score', v_ai.territorial_score,
        'military_score', v_ai.military_score,
        'exploration_score', v_ai.exploration_score,
        'type', v_ai.type
      );
    END LOOP;
    
    -- Sort combined results by rank
    SELECT jsonb_agg(entry ORDER BY (entry->>'rank')::INTEGER)
    INTO v_result
    FROM jsonb_array_elements(v_result) as entry;
    
    RETURN json_build_object('ok', true, 'leaderboard', v_result);
  END;
  $$;
  
  
  ALTER FUNCTION "public"."get_leaderboard"("p_universe_id" "uuid", "p_limit" integer) OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."get_player_trade_routes"("p_user_id" "uuid", "p_universe_id" "uuid") RETURNS json
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
  
  
> CREATE OR REPLACE FUNCTION "public"."list_universes"() RETURNS "jsonb"
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
  
  
> CREATE OR REPLACE FUNCTION "public"."update_port_stock_dynamics"() RETURNS integer
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    port_record RECORD;
    updated_count INTEGER := 0;
    decay_rate NUMERIC := 0.05; -- 5% decay
    regen_rate NUMERIC := 0.10; -- 10% regeneration
    base_stock INTEGER := 1000000000;
  BEGIN
    -- Process each commodity port
    FOR port_record IN 
      SELECT id, kind, ore, organics, goods, energy
      FROM ports 
      WHERE kind IN ('ore', 'organics', 'goods', 'energy')
    LOOP
      -- Decay non-native stock (5% loss)
      -- Regenerate native stock (10% gain toward base_stock)
      UPDATE ports SET
        ore = CASE 
          WHEN port_record.kind = 'ore' THEN 
            LEAST(base_stock, port_record.ore + FLOOR((base_stock - port_record.ore) * regen_rate))
          ELSE 
            GREATEST(0, port_record.ore - FLOOR(port_record.ore * decay_rate))
        END,
        organics = CASE 
          WHEN port_record.kind = 'organics' THEN 
            LEAST(base_stock, port_record.organics + FLOOR((base_stock - port_record.organics) * regen_rate))
          ELSE 
            GREATEST(0, port_record.organics - FLOOR(port_record.organics * decay_rate))
        END,
        goods = CASE 
          WHEN port_record.kind = 'goods' THEN 
            LEAST(base_stock, port_record.goods + FLOOR((base_stock - port_record.goods) * regen_rate))
          ELSE 
            GREATEST(0, port_record.goods - FLOOR(port_record.goods * decay_rate))
        END,
        energy = CASE 
          WHEN port_record.kind = 'energy' THEN 
            LEAST(base_stock, port_record.energy + FLOOR((base_stock - port_record.energy) * regen_rate))
          ELSE 
            GREATEST(0, port_record.energy - FLOOR(port_record.energy * decay_rate))
        END
      WHERE id = port_record.id;
      
      updated_count := updated_count + 1;
    END LOOP;
    
    RETURN updated_count;
  END;
  $$;
  
  
  ALTER FUNCTION "public"."update_port_stock_dynamics"() OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."update_route_stats"("p_route_id" "uuid") RETURNS "void"
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
  
  
> CREATE OR REPLACE FUNCTION "public"."update_universe_rankings"("p_universe_id" "uuid") RETURNS json
      LANGUAGE "plpgsql" SECURITY DEFINER
      AS $$
  DECLARE
    v_player RECORD;
    v_scores JSON;
    v_rank_position INTEGER := 1;
    v_result JSON := '[]'::json;
  BEGIN
    -- Update player rankings
    FOR v_player IN 
      SELECT p.id, p.handle
      FROM players p
      WHERE p.universe_id = p_universe_id
      ORDER BY p.created_at
    LOOP
      -- Calculate scores
      v_scores := calculate_total_score(v_player.id, p_universe_id);
      
      -- Upsert ranking
      INSERT INTO player_rankings (
        player_id, universe_id, 
        economic_score, territorial_score, military_score, exploration_score, total_score,
        last_updated
      )
      VALUES (
        v_player.id, p_universe_id,
        (v_scores->>'economic')::INTEGER,
        (v_scores->>'territorial')::INTEGER,
        (v_scores->>'military')::INTEGER,
        (v_scores->>'exploration')::INTEGER,
        (v_scores->>'total')::INTEGER,
        NOW()
      )
      ON CONFLICT (player_id, universe_id)
      DO UPDATE SET
        economic_score = (v_scores->>'economic')::INTEGER,
        territorial_score = (v_scores->>'territorial')::INTEGER,
        military_score = (v_scores->>'military')::INTEGER,
        exploration_score = (v_scores->>'exploration')::INTEGER,
        total_score = (v_scores->>'total')::INTEGER,
        last_updated = NOW();
    END LOOP;
    
    -- Update rank positions for players
    WITH ranked_players AS (
      SELECT 
        pr.id,
        pr.player_id,
        pr.total_score,
        ROW_NUMBER() OVER (ORDER BY pr.total_score DESC) as new_rank
      FROM player_rankings pr
      WHERE pr.universe_id = p_universe_id
    )
    UPDATE player_rankings pr
    SET rank_position = rp.new_rank
    FROM ranked_players rp
    WHERE pr.id = rp.id;
    
    -- Update rank positions for AI players
    WITH ranked_ai AS (
      SELECT 
        ap.id,
        ap.total_score,
        ROW_NUMBER() OVER (ORDER BY ap.total_score DESC) as new_rank
      FROM ai_players ap
      WHERE ap.universe_id = p_universe_id
    )
    UPDATE ai_players ap
    SET rank_position = ra.new_rank
    FROM ranked_ai ra
    WHERE ap.id = ra.id;
    
    -- Record ranking history
    INSERT INTO ranking_history (
      player_id, universe_id, rank_position, total_score,
      economic_score, territorial_score, military_score, exploration_score
    )
    SELECT 
      pr.player_id, pr.universe_id, pr.rank_position, pr.total_score,
      pr.economic_score, pr.territorial_score, pr.military_score, pr.exploration_score
    FROM player_rankings pr
    WHERE pr.universe_id = p_universe_id;
    
    -- Record AI ranking history
    INSERT INTO ai_ranking_history (
      ai_player_id, universe_id, rank_position, total_score,
      economic_score, territorial_score, military_score, exploration_score
    )
    SELECT 
      ap.id, ap.universe_id, ap.rank_position, ap.total_score,
      ap.economic_score, ap.territorial_score, ap.military_score, ap.exploration_score
    FROM ai_players ap
    WHERE ap.universe_id = p_universe_id;
    
    RETURN json_build_object('ok', true, 'message', 'Rankings updated successfully');
  END;
  $$;
  
  
  ALTER FUNCTION "public"."update_universe_rankings"("p_universe_id" "uuid") OWNER TO "postgres";
  
  
> CREATE OR REPLACE FUNCTION "public"."validate_route_waypoints"("p_route_id" "uuid") RETURNS boolean
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
  
  
  CREATE TABLE IF NOT EXISTS "public"."combats" (
      "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
      "attacker_id" "uuid" NOT NULL,
      "defender_id" "uuid" NOT NULL,
      "outcome" "text",
      "snapshot" "jsonb",
      "at" timestamp with time zone DEFAULT "now"()
  );
  
  
  ALTER TABLE "public"."combats" OWNER TO "postgres";
  
  
  CREATE TABLE IF NOT EXISTS "public"."favorites" (
      "player_id" "uuid" NOT NULL,
      "sector_id" "uuid" NOT NULL
  );
  
  
  ALTER TABLE "public"."favorites" OWNER TO "postgres";
  
  
  CREATE TABLE IF NOT EXISTS "public"."inventories" (
      "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
      "player_id" "uuid" NOT NULL,
      "ore" integer DEFAULT 0,
      "organics" integer DEFAULT 0,
      "goods" integer DEFAULT 0,
      "energy" integer DEFAULT 0,
      "created_at" timestamp with time zone DEFAULT "now"()
  );
  
  
  ALTER TABLE "public"."inventories" OWNER TO "postgres";
  
  
  CREATE TABLE IF NOT EXISTS "public"."planets" (
      "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
      "sector_id" "uuid",
      "owner_player_id" "uuid",
      "name" "text",
      "created_at" timestamp with time zone DEFAULT "now"()
  );
  
  
  ALTER TABLE "public"."planets" OWNER TO "postgres";
  
  
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
      "credits" bigint DEFAULT 1000,
      "turns" integer DEFAULT 60,
      "turn_cap" integer DEFAULT 120,
      "current_sector" "uuid",
      "last_turn_ts" timestamp with time zone DEFAULT "now"(),
      "created_at" timestamp with time zone DEFAULT "now"()
  );
  
  
  ALTER TABLE "public"."players" OWNER TO "postgres";
  
  
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


