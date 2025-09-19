-- Improved Scheduler Settings - Redux Version
-- Streamlined terminology and more consistent scheduling

-- Drop existing function first (if it exists)
DROP FUNCTION IF EXISTS public.get_universe_settings(uuid) CASCADE;

-- Add new improved scheduler columns to universe_settings
ALTER TABLE public.universe_settings 
ADD COLUMN IF NOT EXISTS turn_generation_interval_minutes integer DEFAULT 3,
ADD COLUMN IF NOT EXISTS turns_per_generation integer DEFAULT 4,
ADD COLUMN IF NOT EXISTS cycle_interval_minutes integer DEFAULT 6,
ADD COLUMN IF NOT EXISTS update_interval_minutes integer DEFAULT 1,
ADD COLUMN IF NOT EXISTS last_turn_generation timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_cycle_event timestamp with time zone,
ADD COLUMN IF NOT EXISTS last_update_event timestamp with time zone;

-- Add constraints for new scheduler settings (Postgres does not support IF NOT EXISTS on ADD CONSTRAINT)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'universe_settings_turn_generation_positive') THEN
    ALTER TABLE public.universe_settings DROP CONSTRAINT universe_settings_turn_generation_positive;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'universe_settings_turns_per_gen_positive') THEN
    ALTER TABLE public.universe_settings DROP CONSTRAINT universe_settings_turns_per_gen_positive;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'universe_settings_cycle_interval_positive') THEN
    ALTER TABLE public.universe_settings DROP CONSTRAINT universe_settings_cycle_interval_positive;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'universe_settings_update_interval_positive') THEN
    ALTER TABLE public.universe_settings DROP CONSTRAINT universe_settings_update_interval_positive;
  END IF;
END $$;

ALTER TABLE public.universe_settings 
  ADD CONSTRAINT universe_settings_turn_generation_positive 
    CHECK (turn_generation_interval_minutes > 0),
  ADD CONSTRAINT universe_settings_turns_per_gen_positive 
    CHECK (turns_per_generation > 0),
  ADD CONSTRAINT universe_settings_cycle_interval_positive 
    CHECK (cycle_interval_minutes > 0),
  ADD CONSTRAINT universe_settings_update_interval_positive 
    CHECK (update_interval_minutes > 0);

-- Update the get_universe_settings function to include new fields
CREATE OR REPLACE FUNCTION public.get_universe_settings(p_universe_id uuid)
RETURNS TABLE (
    universe_id uuid,
    game_version text,
    game_name text,
    avg_tech_level_mines integer,
    avg_tech_emergency_warp_degrade integer,
    max_avg_tech_federation_sectors integer,
    tech_level_upgrade_bases integer,
    number_of_sectors integer,
    max_links_per_sector integer,
    max_planets_per_sector integer,
    planets_needed_for_sector_ownership integer,
    igb_enabled boolean,
    igb_interest_rate_per_update numeric,
    igb_loan_rate_per_update numeric,
    planet_interest_rate numeric,
    colonists_limit bigint,
    colonist_production_rate numeric,
    colonists_per_fighter integer,
    colonists_per_torpedo integer,
    colonists_per_ore integer,
    colonists_per_organics integer,
    colonists_per_goods integer,
    colonists_per_energy integer,
    colonists_per_credits integer,
    max_accumulated_turns integer,
    max_traderoutes_per_player integer,
    energy_per_sector_fighter numeric,
    sector_fighter_degradation_rate numeric,
    tick_interval_minutes integer,
    turns_generation_interval_minutes integer,
    turns_per_generation integer,
    defenses_check_interval_minutes integer,
    xenobes_play_interval_minutes integer,
    igb_interest_accumulation_interval_minutes integer,
    news_generation_interval_minutes integer,
    planet_production_interval_minutes integer,
    port_regeneration_interval_minutes integer,
    ships_tow_from_fed_sectors_interval_minutes integer,
    rankings_generation_interval_minutes integer,
    sector_defenses_degrade_interval_minutes integer,
    planetary_apocalypse_interval_minutes integer,
    use_new_planet_update_code boolean,
    limit_captured_planets_max_credits boolean,
    captured_planets_max_credits bigint,
    -- New improved scheduler fields
    turn_generation_interval_minutes integer,
    cycle_interval_minutes integer,
    update_interval_minutes integer,
    last_turn_generation timestamp with time zone,
    last_cycle_event timestamp with time zone,
    last_update_event timestamp with time zone
)
LANGUAGE plpgsql
STABLE
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
        -- New fields
        us.turn_generation_interval_minutes,
        us.cycle_interval_minutes,
        us.update_interval_minutes,
        us.last_turn_generation,
        us.last_cycle_event,
        us.last_update_event
    FROM public.universe_settings us
    WHERE us.universe_id = p_universe_id;
    
    -- If no settings found, return defaults
    IF NOT FOUND THEN
        RETURN QUERY
        SELECT 
            p_universe_id,
            '0.663'::text,
            'BNT Redux'::text,
            13,
            15,
            8,
            1,
            1000,
            10,
            10,
            5,
            true,
            0.05::numeric,
            0.1::numeric,
            0.06::numeric,
            100000000000::bigint,
            0.005::numeric,
            20000,
            8000,
            800,
            400,
            800,
            400,
            67,
            5000,
            40,
            0.1::numeric,
            5.0::numeric,
            6,
            3,
            12,
            3,
            3,
            2,
            6,
            2,
            1,
            3,
            1,
            6,
            60,
            true,
            false,
            1000000000::bigint,
            -- New defaults
            3,
            4,
            6,
            1,
            NULL::timestamp with time zone,
            NULL::timestamp with time zone,
            NULL::timestamp with time zone;
    END IF;
END;
$$;

-- Function to get next scheduled events for a universe
CREATE OR REPLACE FUNCTION public.get_next_scheduled_events(p_universe_id uuid)
RETURNS TABLE (
    next_turn_generation timestamp with time zone,
    next_cycle_event timestamp with time zone,
    next_update_event timestamp with time zone,
    turns_until_next_turn_generation integer,
    minutes_until_next_cycle integer,
    minutes_until_next_update integer
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_settings RECORD;
    v_now timestamp with time zone := now();
BEGIN
    -- Get universe settings
    SELECT * INTO v_settings FROM public.universe_settings WHERE universe_id = p_universe_id;
    
    -- If no settings found, return nulls
    IF NOT FOUND THEN
        RETURN QUERY SELECT NULL, NULL, NULL, NULL, NULL, NULL;
        RETURN;
    END IF;
    
    -- Calculate next events
    RETURN QUERY
    SELECT 
        -- Next turn generation
        CASE 
            WHEN v_settings.last_turn_generation IS NULL THEN v_now
            ELSE v_settings.last_turn_generation + (v_settings.turn_generation_interval_minutes || ' minutes')::interval
        END,
        -- Next cycle event
        CASE 
            WHEN v_settings.last_cycle_event IS NULL THEN v_now
            ELSE v_settings.last_cycle_event + (v_settings.cycle_interval_minutes || ' minutes')::interval
        END,
        -- Next update event
        CASE 
            WHEN v_settings.last_update_event IS NULL THEN v_now
            ELSE v_settings.last_update_event + (v_settings.update_interval_minutes || ' minutes')::interval
        END,
        -- Turns until next generation (always 0 since we don't track individual turns)
        0,
        -- Minutes until next cycle
        CASE 
            WHEN v_settings.last_cycle_event IS NULL THEN 0
            ELSE GREATEST(0, EXTRACT(EPOCH FROM (v_settings.last_cycle_event + (v_settings.cycle_interval_minutes || ' minutes')::interval - v_now)) / 60)::integer
        END,
        -- Minutes until next update
        CASE 
            WHEN v_settings.last_update_event IS NULL THEN 0
            ELSE GREATEST(0, EXTRACT(EPOCH FROM (v_settings.last_update_event + (v_settings.update_interval_minutes || ' minutes')::interval - v_now)) / 60)::integer
        END;
END;
$$;

-- Function to update scheduler timestamps
CREATE OR REPLACE FUNCTION public.update_scheduler_timestamp(
    p_universe_id uuid,
    p_event_type text,
    p_timestamp timestamp with time zone DEFAULT now()
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    CASE p_event_type
        WHEN 'turn_generation' THEN
            UPDATE public.universe_settings 
            SET last_turn_generation = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'cycle_event' THEN
            UPDATE public.universe_settings 
            SET last_cycle_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'update_event' THEN
            UPDATE public.universe_settings 
            SET last_update_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        ELSE
            RETURN false;
    END CASE;
    
    RETURN true;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_next_scheduled_events(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_scheduler_timestamp(uuid, text, timestamp with time zone) TO authenticated;

-- Set ownership
ALTER FUNCTION public.get_next_scheduled_events(uuid) OWNER TO postgres;
ALTER FUNCTION public.update_scheduler_timestamp(uuid, text, timestamp with time zone) OWNER TO postgres;
