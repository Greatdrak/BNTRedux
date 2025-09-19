-- Planet System Overhaul - Classic BNT Implementation
-- This migration expands the planets table with all necessary fields for classic BNT functionality

BEGIN;

-- ============================================================================
-- 1. EXPAND PLANETS TABLE WITH CLASSIC BNT FIELDS
-- ============================================================================

-- Add all the missing fields to the planets table
ALTER TABLE public.planets 
ADD COLUMN IF NOT EXISTS colonists bigint DEFAULT 0 CHECK (colonists >= 0),
ADD COLUMN IF NOT EXISTS colonists_max bigint DEFAULT 100000000 CHECK (colonists_max > 0),
ADD COLUMN IF NOT EXISTS ore bigint DEFAULT 0 CHECK (ore >= 0),
ADD COLUMN IF NOT EXISTS organics bigint DEFAULT 0 CHECK (organics >= 0),
ADD COLUMN IF NOT EXISTS goods bigint DEFAULT 0 CHECK (goods >= 0),
ADD COLUMN IF NOT EXISTS energy bigint DEFAULT 0 CHECK (energy >= 0),
ADD COLUMN IF NOT EXISTS fighters integer DEFAULT 0 CHECK (fighters >= 0),
ADD COLUMN IF NOT EXISTS torpedoes integer DEFAULT 0 CHECK (torpedoes >= 0),
ADD COLUMN IF NOT EXISTS shields integer DEFAULT 0 CHECK (shields >= 0),
ADD COLUMN IF NOT EXISTS last_production timestamp with time zone DEFAULT now(),
ADD COLUMN IF NOT EXISTS last_colonist_growth timestamp with time zone DEFAULT now();

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_planets_owner_player_id ON public.planets(owner_player_id);
CREATE INDEX IF NOT EXISTS idx_planets_last_production ON public.planets(last_production);
CREATE INDEX IF NOT EXISTS idx_planets_last_colonist_growth ON public.planets(last_colonist_growth);

-- ============================================================================
-- 2. UPDATE EXISTING PLANET RPC FUNCTIONS FOR NEW SCHEMA
-- ============================================================================

-- Update game_planet_claim to initialize new fields
DROP FUNCTION IF EXISTS public.game_planet_claim(uuid, integer, text, uuid);

CREATE OR REPLACE FUNCTION public.game_planet_claim(
  p_user_id uuid,
  p_sector_number integer,
  p_name text DEFAULT 'Colony',
  p_universe_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid;
  v_sector_id uuid;
  v_planet_id uuid;
  v_player_credits bigint;
  v_player_turns integer;
  v_cost_credits bigint := 10000;
  v_cost_turns integer := 5;
  v_result json;
BEGIN
  -- Get player info
  SELECT id, credits, turns INTO v_player_id, v_player_credits, v_player_turns
  FROM players 
  WHERE user_id = p_user_id 
    AND universe_id = COALESCE(p_universe_id, universe_id);
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
  END IF;
  
  -- Check if player has enough credits and turns
  IF v_player_credits < v_cost_credits THEN
    RETURN json_build_object('error', json_build_object('code', 'insufficient_credits', 'message', 'Need 10,000 credits to claim planet'));
  END IF;
  
  IF v_player_turns < v_cost_turns THEN
    RETURN json_build_object('error', json_build_object('code', 'insufficient_turns', 'message', 'Need 5 turns to claim planet'));
  END IF;
  
  -- Get sector ID
  SELECT id INTO v_sector_id
  FROM sectors 
  WHERE number = p_sector_number 
    AND universe_id = COALESCE(p_universe_id, (SELECT universe_id FROM players WHERE id = v_player_id));
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', json_build_object('code', 'sector_not_found', 'message', 'Sector not found'));
  END IF;
  
  -- Check if sector already has a planet
  IF EXISTS (SELECT 1 FROM planets WHERE sector_id = v_sector_id) THEN
    RETURN json_build_object('error', json_build_object('code', 'planet_exists', 'message', 'Sector already has a planet'));
  END IF;
  
  -- Create the planet with initial values
  INSERT INTO planets (
    sector_id, 
    owner_player_id, 
    name,
    colonists,
    colonists_max,
    ore,
    organics,
    goods,
    energy,
    fighters,
    torpedoes,
    shields,
    last_production,
    last_colonist_growth
  ) VALUES (
    v_sector_id, 
    v_player_id, 
    p_name,
    1000, -- Start with 1000 colonists
    100000000, -- Max 100M colonists
    0, 0, 0, 0, -- No initial resources
    0, 0, 0, -- No initial defenses
    now(),
    now()
  ) RETURNING id INTO v_planet_id;
  
  -- Deduct costs from player
  UPDATE players 
  SET credits = credits - v_cost_credits,
      turns = turns - v_cost_turns
  WHERE id = v_player_id;
  
  RETURN json_build_object(
    'success', true,
    'planet_id', v_planet_id,
    'planet_name', p_name,
    'cost_credits', v_cost_credits,
    'cost_turns', v_cost_turns,
    'remaining_credits', v_player_credits - v_cost_credits,
    'remaining_turns', v_player_turns - v_cost_turns
  );
END;
$$;

-- Update game_planet_store to work with new schema
DROP FUNCTION IF EXISTS public.game_planet_store(uuid, uuid, text, integer);

CREATE OR REPLACE FUNCTION public.game_planet_store(
  p_user_id uuid,
  p_planet uuid,
  p_resource text,
  p_qty integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Update game_planet_withdraw to work with new schema
DROP FUNCTION IF EXISTS public.game_planet_withdraw(uuid, uuid, text, integer);

CREATE OR REPLACE FUNCTION public.game_planet_withdraw(
  p_user_id uuid,
  p_planet uuid,
  p_resource text,
  p_qty integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
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

-- ============================================================================
-- 3. CREATE PLANET PRODUCTION RPC FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.run_planet_production(p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  planet_record RECORD;
  v_planets_processed integer := 0;
  v_colonists_grown integer := 0;
  v_resources_produced integer := 0;
  v_settings RECORD;
  v_growth_rate numeric;
  v_production_rate numeric;
  v_new_colonists bigint;
  v_produced_ore bigint;
  v_produced_organics bigint;
  v_produced_goods bigint;
  v_produced_energy bigint;
BEGIN
  -- Get universe settings for production rates
  SELECT 
    colonist_production_rate,
    colonists_per_ore,
    colonists_per_organics,
    colonists_per_goods,
    colonists_per_energy
  INTO v_settings
  FROM universe_settings 
  WHERE universe_id = p_universe_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Universe settings not found');
  END IF;
  
  v_growth_rate := v_settings.colonist_production_rate;
  
  -- Process each planet
  FOR planet_record IN 
    SELECT p.id, p.colonists, p.colonists_max, p.ore, p.organics, p.goods, p.energy, p.last_colonist_growth, p.last_production
    FROM planets p
    JOIN sectors s ON s.id = p.sector_id
    WHERE s.universe_id = p_universe_id 
      AND p.owner_player_id IS NOT NULL
  LOOP
    v_planets_processed := v_planets_processed + 1;
    
    -- Colonist growth (if not at max)
    IF planet_record.colonists < planet_record.colonists_max THEN
      v_new_colonists := LEAST(
        planet_record.colonists_max,
        planet_record.colonists + FLOOR(planet_record.colonists * v_growth_rate)
      );
      
      IF v_new_colonists > planet_record.colonists THEN
        v_colonists_grown := v_colonists_grown + 1;
        
        UPDATE planets 
        SET colonists = v_new_colonists,
            last_colonist_growth = now()
        WHERE id = planet_record.id;
      END IF;
    END IF;
    
    -- Resource production based on colonists
    v_produced_ore := FLOOR(planet_record.colonists / v_settings.colonists_per_ore);
    v_produced_organics := FLOOR(planet_record.colonists / v_settings.colonists_per_organics);
    v_produced_goods := FLOOR(planet_record.colonists / v_settings.colonists_per_goods);
    v_produced_energy := FLOOR(planet_record.colonists / v_settings.colonists_per_energy);
    
    -- Update planet resources
    UPDATE planets 
    SET 
      ore = ore + v_produced_ore,
      organics = organics + v_produced_organics,
      goods = goods + v_produced_goods,
      energy = energy + v_produced_energy,
      last_production = now()
    WHERE id = planet_record.id;
    
    v_resources_produced := v_resources_produced + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'planets_processed', v_planets_processed,
    'colonists_grown', v_colonists_grown,
    'resources_produced', v_resources_produced,
    'universe_id', p_universe_id
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.game_planet_claim(uuid, integer, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_planet_claim(uuid, integer, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.game_planet_store(uuid, uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_planet_store(uuid, uuid, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.game_planet_withdraw(uuid, uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_planet_withdraw(uuid, uuid, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.run_planet_production(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.run_planet_production(uuid) TO service_role;

COMMIT;
