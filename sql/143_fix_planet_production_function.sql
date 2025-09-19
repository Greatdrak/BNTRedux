-- Migration: Fix planet production function to include credits and interest
-- This migration updates the run_planet_production function to return the correct fields

-- Drop existing function first
DROP FUNCTION IF EXISTS public.run_planet_production(uuid);

-- Create the updated planet production RPC function
CREATE OR REPLACE FUNCTION public.run_planet_production(
  p_universe_id uuid
)
RETURNS TABLE(
  planets_processed integer,
  colonists_grown integer,
  resources_produced integer,
  credits_produced integer,
  interest_generated integer
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
  v_credits_produced integer := 0;
  v_interest_generated integer := 0;
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
  v_interest_amount bigint;
  v_total_allocation integer;
  v_remaining_percent integer;
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
  
  -- If no settings found, use defaults
  IF NOT FOUND THEN
    v_settings.colonist_production_rate := 0.1;
    v_settings.colonists_per_ore := 100;
    v_settings.colonists_per_organics := 100;
    v_settings.colonists_per_goods := 100;
    v_settings.colonists_per_energy := 100;
    v_settings.colonists_per_fighter := 50;
    v_settings.colonists_per_torpedo := 50;
    v_settings.colonists_per_credits := 10;
    v_settings.planet_interest_rate := 0.05;
  END IF;
  
  -- Process each owned planet
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
      p.credits,
      p.production_ore_percent,
      p.production_organics_percent,
      p.production_goods_percent,
      p.production_energy_percent,
      p.production_fighters_percent,
      p.production_torpedoes_percent
    FROM planets p
    JOIN sectors s ON p.sector_id = s.id
    WHERE s.universe_id = p_universe_id
      AND p.owner_player_id IS NOT NULL
  LOOP
    v_planets_processed := v_planets_processed + 1;
    
    -- Calculate colonist growth
    v_growth_rate := v_settings.colonist_production_rate;
    v_new_colonists := FLOOR(planet_record.colonists * v_growth_rate);
    
    -- Add new colonists (up to max)
    v_new_colonists := LEAST(v_new_colonists, planet_record.colonists_max - planet_record.colonists);
    v_colonists_grown := v_colonists_grown + v_new_colonists;
    
    -- Calculate production colonists (new + existing)
    v_production_colonists := planet_record.colonists + v_new_colonists;
    
    -- Calculate total allocation percentage
    v_total_allocation := COALESCE(planet_record.production_ore_percent, 0) +
                         COALESCE(planet_record.production_organics_percent, 0) +
                         COALESCE(planet_record.production_goods_percent, 0) +
                         COALESCE(planet_record.production_energy_percent, 0) +
                         COALESCE(planet_record.production_fighters_percent, 0) +
                         COALESCE(planet_record.production_torpedoes_percent, 0);
    
    -- Calculate remaining percentage for credits
    v_remaining_percent := 100 - v_total_allocation;
    
    -- Calculate production based on allocation percentages
    v_produced_ore := FLOOR((v_production_colonists * COALESCE(planet_record.production_ore_percent, 0) / 100) / v_settings.colonists_per_ore);
    v_produced_organics := FLOOR((v_production_colonists * COALESCE(planet_record.production_organics_percent, 0) / 100) / v_settings.colonists_per_organics);
    v_produced_goods := FLOOR((v_production_colonists * COALESCE(planet_record.production_goods_percent, 0) / 100) / v_settings.colonists_per_goods);
    v_produced_energy := FLOOR((v_production_colonists * COALESCE(planet_record.production_energy_percent, 0) / 100) / v_settings.colonists_per_energy);
    v_produced_fighters := FLOOR((v_production_colonists * COALESCE(planet_record.production_fighters_percent, 0) / 100) / v_settings.colonists_per_fighter);
    v_produced_torpedoes := FLOOR((v_production_colonists * COALESCE(planet_record.production_torpedoes_percent, 0) / 100) / v_settings.colonists_per_torpedo);
    v_produced_credits := FLOOR((v_production_colonists * v_remaining_percent / 100) / v_settings.colonists_per_credits);
    
    -- Calculate interest on existing credits
    v_interest_amount := FLOOR(planet_record.credits * v_settings.planet_interest_rate);
    
    -- Update planet resources
    UPDATE planets
    SET 
      colonists = LEAST(colonists + v_new_colonists, colonists_max),
      ore = ore + v_produced_ore,
      organics = organics + v_produced_organics,
      goods = goods + v_produced_goods,
      energy = energy + v_produced_energy,
      fighters = fighters + v_produced_fighters,
      torpedoes = torpedoes + v_produced_torpedoes,
      credits = credits + v_produced_credits + v_interest_amount,
      last_production = NOW(),
      last_colonist_growth = NOW()
    WHERE id = planet_record.id;
    
    -- Add to totals
    v_resources_produced := v_resources_produced + v_produced_ore + v_produced_organics + v_produced_goods + v_produced_energy + v_produced_fighters + v_produced_torpedoes;
    v_credits_produced := v_credits_produced + v_produced_credits;
    v_interest_generated := v_interest_generated + v_interest_amount;
  END LOOP;
  
  RETURN QUERY SELECT v_planets_processed, v_colonists_grown, v_resources_produced, v_credits_produced, v_interest_generated;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.run_planet_production(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.run_planet_production(uuid) TO service_role;
