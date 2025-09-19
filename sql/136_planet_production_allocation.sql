-- Planet Production Allocation System
-- Implements the original BNT percentage-based production allocation

-- Add production allocation fields to planets table
ALTER TABLE public.planets 
ADD COLUMN IF NOT EXISTS production_ore_percent integer DEFAULT 0 CHECK (production_ore_percent >= 0 AND production_ore_percent <= 100),
ADD COLUMN IF NOT EXISTS production_organics_percent integer DEFAULT 0 CHECK (production_organics_percent >= 0 AND production_organics_percent <= 100),
ADD COLUMN IF NOT EXISTS production_goods_percent integer DEFAULT 0 CHECK (production_goods_percent >= 0 AND production_goods_percent <= 100),
ADD COLUMN IF NOT EXISTS production_energy_percent integer DEFAULT 0 CHECK (production_energy_percent >= 0 AND production_energy_percent <= 100),
ADD COLUMN IF NOT EXISTS production_fighters_percent integer DEFAULT 0 CHECK (production_fighters_percent >= 0 AND production_fighters_percent <= 100),
ADD COLUMN IF NOT EXISTS production_torpedoes_percent integer DEFAULT 0 CHECK (production_torpedoes_percent >= 0 AND production_torpedoes_percent <= 100);

-- Add constraint to ensure total allocation doesn't exceed 100%
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'planets_production_allocation_check' 
    AND table_name = 'planets'
  ) THEN
    ALTER TABLE public.planets DROP CONSTRAINT planets_production_allocation_check;
  END IF;
END $$;

ALTER TABLE public.planets 
ADD CONSTRAINT planets_production_allocation_check 
CHECK (
  production_ore_percent + 
  production_organics_percent + 
  production_goods_percent + 
  production_energy_percent +
  production_fighters_percent +
  production_torpedoes_percent <= 100
);

-- Drop existing function first (if it exists)
DROP FUNCTION IF EXISTS public.run_planet_production(uuid);

-- Create the planet production RPC function
CREATE OR REPLACE FUNCTION public.run_planet_production(
  p_universe_id uuid
)
RETURNS TABLE(
  planets_processed integer,
  colonists_grown integer,
  resources_produced integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  planet_record RECORD;
  v_settings RECORD;
  v_planets_processed integer := 0;
  v_colonists_grown integer := 0;
  v_resources_produced integer := 0;
  v_growth_rate numeric;
  v_new_colonists bigint;
  v_production_colonists bigint;
  v_produced_ore bigint;
  v_produced_organics bigint;
  v_produced_goods bigint;
  v_produced_energy bigint;
  v_produced_fighters bigint;
  v_produced_torpedoes bigint;
  v_produced_credits bigint;
  v_total_allocation integer;
  v_remaining_percent integer;
BEGIN
  -- Get universe settings for production rates
  SELECT 
    colonist_production_rate,
    colonists_per_ore,
    colonists_per_organics,
    colonists_per_goods,
    colonists_per_energy,
    colonists_per_fighter,
    colonists_per_torpedo,
    colonists_per_credits
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
          p.production_ore_percent,
          p.production_organics_percent,
          p.production_goods_percent,
          p.production_energy_percent,
          p.production_fighters_percent,
          p.production_torpedoes_percent,
      p.owner_player_id,
      p.last_colonist_growth, 
      p.last_production
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
      
      -- Calculate credits from remaining colonists
      IF v_remaining_percent > 0 THEN
        v_production_colonists := FLOOR(planet_record.colonists * v_remaining_percent / 100.0);
        v_produced_credits := FLOOR(v_production_colonists / v_settings.colonists_per_credits);
      ELSE
        v_produced_credits := 0;
      END IF;
      
      -- Update planet resources
      UPDATE planets 
      SET 
        ore = ore + v_produced_ore,
        organics = organics + v_produced_organics,
        goods = goods + v_produced_goods,
        energy = energy + v_produced_energy,
        fighters = fighters + v_produced_fighters,
        torpedoes = torpedoes + v_produced_torpedoes,
        last_production = now()
      WHERE id = planet_record.id;
      
      -- Add credits to player
      IF v_produced_credits > 0 THEN
        UPDATE players 
        SET credits = credits + v_produced_credits
        WHERE id = planet_record.owner_player_id;
      END IF;
      
      -- Count total resources produced
      v_resources_produced := v_resources_produced + v_produced_ore + v_produced_organics + v_produced_goods + v_produced_energy + v_produced_credits;
    END IF;
  END LOOP;

  RETURN QUERY SELECT v_planets_processed, v_colonists_grown, v_resources_produced;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.run_planet_production(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.run_planet_production(uuid) TO service_role;

-- Create function to update planet production allocation
CREATE OR REPLACE FUNCTION public.update_planet_production_allocation(
  p_planet_id uuid,
  p_ore_percent integer,
  p_organics_percent integer,
  p_goods_percent integer,
  p_energy_percent integer,
  p_fighters_percent integer,
  p_torpedoes_percent integer,
  p_player_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.update_planet_production_allocation(uuid, integer, integer, integer, integer, integer, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planet_production_allocation(uuid, integer, integer, integer, integer, integer, integer, uuid) TO service_role;

-- Fix game_planet_claim to allow claiming unowned planets
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
  v_existing_planet_id uuid;
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
  
  -- Check if sector has a planet
  SELECT id INTO v_existing_planet_id
  FROM planets 
  WHERE sector_id = v_sector_id;
  
  IF NOT FOUND THEN
    -- No planet exists in this sector
    RETURN json_build_object('error', json_build_object('code', 'no_planet', 'message', 'No planet exists in this sector. Use a Genesis Torpedo to create one.'));
  END IF;
  
  -- Planet exists, check if it's already owned
  IF EXISTS (SELECT 1 FROM planets WHERE sector_id = v_sector_id AND owner_player_id IS NOT NULL) THEN
    RETURN json_build_object('error', json_build_object('code', 'planet_owned', 'message', 'Planet is already owned by another player'));
  END IF;
  
  -- Planet exists and is unowned, claim it
  UPDATE planets 
  SET 
    owner_player_id = v_player_id,
    name = p_name,
    colonists = 1000,
    colonists_max = 100000000,
    ore = 0,
    organics = 0,
    goods = 0,
    energy = 0,
    fighters = 0,
    torpedoes = 0,
    shields = 0,
    last_production = now(),
    last_colonist_growth = now(),
    production_ore_percent = 0,
    production_organics_percent = 0,
    production_goods_percent = 0,
    production_energy_percent = 0
  WHERE sector_id = v_sector_id;
  
  v_planet_id := v_existing_planet_id;
  
  -- Deduct costs from player
  UPDATE players 
  SET credits = credits - v_cost_credits,
      turns = turns - v_cost_turns
  WHERE id = v_player_id;
  
  RETURN json_build_object(
    'success', true,
    'planet_id', v_planet_id,
    'planet_name', p_name,
    'credits_spent', v_cost_credits,
    'turns_spent', v_cost_turns
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.game_planet_claim(uuid, integer, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_planet_claim(uuid, integer, text, uuid) TO service_role;
