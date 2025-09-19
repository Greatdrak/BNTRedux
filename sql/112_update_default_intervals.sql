-- Update default intervals to be more reasonable
-- This prevents events from running every minute and reduces server load

-- Update existing universe_settings to use more reasonable intervals
UPDATE public.universe_settings 
SET 
    port_regeneration_interval_minutes = 5,  -- Changed from 1 to 5 minutes
    rankings_generation_interval_minutes = 10,  -- Changed from 1 to 10 minutes
    defenses_check_interval_minutes = 15,  -- Changed from 3 to 15 minutes
    xenobes_play_interval_minutes = 30,  -- Changed from 3 to 30 minutes
    igb_interest_accumulation_interval_minutes = 10,  -- Changed from 2 to 10 minutes
    news_generation_interval_minutes = 60,  -- Changed from 6 to 60 minutes
    planet_production_interval_minutes = 15,  -- Changed from 2 to 15 minutes
    ships_tow_from_fed_sectors_interval_minutes = 30,  -- Changed from 3 to 30 minutes
    sector_defenses_degrade_interval_minutes = 60,  -- Changed from 6 to 60 minutes
    planetary_apocalypse_interval_minutes = 1440,  -- Changed from 60 to 1440 minutes (24 hours)
WHERE 
    port_regeneration_interval_minutes <= 2  -- Only update if currently set to very short intervals
    OR rankings_generation_interval_minutes <= 2
    OR defenses_check_interval_minutes <= 5
    OR xenobes_play_interval_minutes <= 5
    OR igb_interest_accumulation_interval_minutes <= 5
    OR planet_production_interval_minutes <= 5
    OR ships_tow_from_fed_sectors_interval_minutes <= 5;

-- Update the default values in the table schema for new universes
ALTER TABLE public.universe_settings 
ALTER COLUMN port_regeneration_interval_minutes SET DEFAULT 5,
ALTER COLUMN rankings_generation_interval_minutes SET DEFAULT 10,
ALTER COLUMN defenses_check_interval_minutes SET DEFAULT 15,
ALTER COLUMN xenobes_play_interval_minutes SET DEFAULT 30,
ALTER COLUMN igb_interest_accumulation_interval_minutes SET DEFAULT 10,
ALTER COLUMN news_generation_interval_minutes SET DEFAULT 60,
ALTER COLUMN planet_production_interval_minutes SET DEFAULT 15,
ALTER COLUMN ships_tow_from_fed_sectors_interval_minutes SET DEFAULT 30,
ALTER COLUMN sector_defenses_degrade_interval_minutes SET DEFAULT 60,
ALTER COLUMN planetary_apocalypse_interval_minutes SET DEFAULT 1440;

-- Verify the changes
SELECT 
    u.name as universe_name,
    us.port_regeneration_interval_minutes,
    us.rankings_generation_interval_minutes,
    us.defenses_check_interval_minutes,
    us.xenobes_play_interval_minutes,
    us.igb_interest_accumulation_interval_minutes,
    us.news_generation_interval_minutes,
    us.planet_production_interval_minutes,
    us.ships_tow_from_fed_sectors_interval_minutes,
    us.sector_defenses_degrade_interval_minutes,
    us.planetary_apocalypse_interval_minutes
FROM public.universes u
JOIN public.universe_settings us ON u.id = us.universe_id
ORDER BY u.name;
