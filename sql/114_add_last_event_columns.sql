-- Add missing last_* event columns to universe_settings table
-- These columns track when each event type was last executed

ALTER TABLE public.universe_settings 
ADD COLUMN IF NOT EXISTS last_turn_generation timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_port_regeneration_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_rankings_generation_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_defenses_check_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_xenobes_play_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_igb_interest_accumulation_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_news_generation_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_planet_production_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_ships_tow_from_fed_sectors_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_sector_defenses_degrade_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_planetary_apocalypse_event timestamp with time zone;

-- Add comments to document what these columns track
COMMENT ON COLUMN public.universe_settings.last_turn_generation IS 'Timestamp when turn generation was last executed';
COMMENT ON COLUMN public.universe_settings.last_port_regeneration_event IS 'Timestamp when port regeneration was last executed';
COMMENT ON COLUMN public.universe_settings.last_rankings_generation_event IS 'Timestamp when rankings generation was last executed';
COMMENT ON COLUMN public.universe_settings.last_defenses_check_event IS 'Timestamp when defenses check was last executed';
COMMENT ON COLUMN public.universe_settings.last_xenobes_play_event IS 'Timestamp when xenobes play was last executed';
COMMENT ON COLUMN public.universe_settings.last_igb_interest_accumulation_event IS 'Timestamp when IGB interest accumulation was last executed';
COMMENT ON COLUMN public.universe_settings.last_news_generation_event IS 'Timestamp when news generation was last executed';
COMMENT ON COLUMN public.universe_settings.last_planet_production_event IS 'Timestamp when planet production was last executed';
COMMENT ON COLUMN public.universe_settings.last_ships_tow_from_fed_sectors_event IS 'Timestamp when ships tow from fed sectors was last executed';
COMMENT ON COLUMN public.universe_settings.last_sector_defenses_degrade_event IS 'Timestamp when sector defenses degrade was last executed';
COMMENT ON COLUMN public.universe_settings.last_planetary_apocalypse_event IS 'Timestamp when planetary apocalypse was last executed';
