-- Planet Credits and Interest System
-- Adds credits storage to planets and implements interest generation

-- Add credits field to planets table
ALTER TABLE public.planets 
ADD COLUMN IF NOT EXISTS credits bigint DEFAULT 0 CHECK (credits >= 0);

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_planets_credits ON public.planets(credits);

-- Update the planet production function to include interest generation
DROP FUNCTION IF EXISTS public.run_planet_production(uuid);

CREATE OR REPLACE FUNCTION public.run_planet_production(
  p_universe_id uuid
)
RETURNS TABLE(
  planets_processed integer,
  colonists_grown integer,
  resources_produced integer,
  credits_produced bigint,
  interest_generated bigint
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
  v_credits_produced bigint := 0;
  v_interest_generated bigint := 0;
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
  v_interest_rate numeric;
  v_planet_interest bigint;
BEGIN
  -- Get universe settings for production rates and interest
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
  v_interest_rate := v_settings.planet_interest_rate;
  
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
      p.credits,
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
      
      -- Calculate interest on existing planet credits
      IF planet_record.credits > 0 THEN
        v_planet_interest := FLOOR(planet_record.credits * v_interest_rate);
      ELSE
        v_planet_interest := 0;
      END IF;
      
      -- Update planet resources and credits
      UPDATE planets 
      SET 
        ore = ore + v_produced_ore,
        organics = organics + v_produced_organics,
        goods = goods + v_produced_goods,
        energy = energy + v_produced_energy,
        fighters = fighters + v_produced_fighters,
        torpedoes = torpedoes + v_produced_torpedoes,
        credits = credits + v_produced_credits + v_planet_interest,
        last_production = now()
      WHERE id = planet_record.id;
      
      IF v_produced_ore > 0 OR v_produced_organics > 0 OR v_produced_goods > 0 OR v_produced_energy > 0 OR v_produced_fighters > 0 OR v_produced_torpedoes > 0 THEN
        v_resources_produced := v_resources_produced + 1;
      END IF;
      
      IF v_produced_credits > 0 THEN
        v_credits_produced := v_credits_produced + v_produced_credits;
      END IF;
      
      IF v_planet_interest > 0 THEN
        v_interest_generated := v_interest_generated + v_planet_interest;
      END IF;
    END IF;
    
  END LOOP;
  
  RETURN QUERY SELECT v_planets_processed, v_colonists_grown, v_resources_produced, v_credits_produced, v_interest_generated;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.run_planet_production(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.run_planet_production(uuid) TO service_role;
