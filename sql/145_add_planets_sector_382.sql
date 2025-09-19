-- Add two more planets in sector 382 (universe alpha)
-- This respects the universe setting for maximum planets per sector

-- First, remove the unique constraint that prevents multiple planets per sector
ALTER TABLE public.planets DROP CONSTRAINT IF EXISTS planets_unique_sector;

-- Get the universe_id for alpha universe
DO $$
DECLARE
    alpha_universe_id UUID;
    sector_382_id UUID;
    max_planets_limit INTEGER;
    current_planet_count INTEGER;
BEGIN
    -- Get universe_id for alpha
    SELECT id INTO alpha_universe_id FROM public.universes WHERE name = 'Alpha';
    
    IF alpha_universe_id IS NULL THEN
        RAISE EXCEPTION 'Universe "Alpha" not found';
    END IF;
    
    -- Get sector_id for sector 382 in alpha universe
    SELECT id INTO sector_382_id FROM public.sectors 
    WHERE universe_id = alpha_universe_id AND number = 382;
    
    IF sector_382_id IS NULL THEN
        RAISE EXCEPTION 'Sector 382 not found in universe Alpha';
    END IF;
    
    -- Get the maximum planets per sector setting
    SELECT max_planets_per_sector INTO max_planets_limit 
    FROM public.universe_settings 
    WHERE universe_id = alpha_universe_id;
    
    -- Default to 3 if setting doesn't exist
    IF max_planets_limit IS NULL THEN
        max_planets_limit := 3;
    END IF;
    
    -- Count current planets in this sector
    SELECT COUNT(*) INTO current_planet_count 
    FROM public.planets 
    WHERE sector_id = sector_382_id;
    
    -- Check if we can add more planets
    IF current_planet_count >= max_planets_limit THEN
        RAISE EXCEPTION 'Sector 382 already has % planets (max allowed: %). Cannot add more planets.', 
            current_planet_count, max_planets_limit;
    END IF;
    
    -- Check if adding 2 planets would exceed the limit
    IF current_planet_count + 2 > max_planets_limit THEN
        RAISE EXCEPTION 'Adding 2 planets would exceed the sector limit. Current: %, Max: %, Would be: %', 
            current_planet_count, max_planets_limit, current_planet_count + 2;
    END IF;
    
    -- Insert two new planets in sector 382
    INSERT INTO public.planets (
        sector_id,
        name,
        colonists,
        colonists_max,
        ore,
        organics,
        goods,
        energy,
        fighters,
        torpedoes,
        credits,
        production_ore_percent,
        production_organics_percent,
        production_goods_percent,
        production_energy_percent,
        production_fighters_percent,
        production_torpedoes_percent,
        base_built,
        base_cost,
        base_colonists_required,
        base_resources_required
    ) VALUES 
    (
        sector_382_id,
        'New Terra',
        50000,
        100000000,
        25000,
        30000,
        20000,
        15000,
        100,
        50,
        50000,
        20,
        20,
        20,
        20,
        10,
        10,
        false,
        50000,
        10000,
        10000
    ),
    (
        sector_382_id,
        'Aurora Prime',
        75000,
        100000000,
        40000,
        35000,
        25000,
        20000,
        150,
        75,
        75000,
        25,
        25,
        25,
        15,
        5,
        5,
        false,
        50000,
        10000,
        10000
    );
    
    RAISE NOTICE 'Successfully created 2 new planets in sector 382: New Terra and Aurora Prime';
    RAISE NOTICE 'Sector 382 now has % planets (max allowed: %)', current_planet_count + 2, max_planets_limit;
END $$;
