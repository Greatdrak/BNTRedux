-- Universe Settings Table - Stage 1: Database Schema & Core Infrastructure
-- Supports multiple universes with individual configuration parameters
-- Based on BNT 0.663 settings from https://mybnt.net/bnt/settings.php

-- Drop existing function first (if it exists)
DROP FUNCTION IF EXISTS public.get_universe_settings(uuid) CASCADE;

-- Drop existing table if it exists
DROP TABLE IF EXISTS public.universe_settings CASCADE;

-- Create universe_settings table with all BNT configuration parameters
CREATE TABLE public.universe_settings (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    universe_id uuid NOT NULL REFERENCES public.universes(id) ON DELETE CASCADE,
    
    -- Game Version & Identity
    game_version text DEFAULT '0.663',
    game_name text DEFAULT 'BNT Redux',
    
    -- Game Mechanics
    avg_tech_level_mines integer DEFAULT 13,
    avg_tech_emergency_warp_degrade integer DEFAULT 15,
    max_avg_tech_federation_sectors integer DEFAULT 8,
    tech_level_upgrade_bases integer DEFAULT 1,
    
    -- Universe Structure
    number_of_sectors integer DEFAULT 1000,
    max_links_per_sector integer DEFAULT 10,
    max_planets_per_sector integer DEFAULT 10,
    planets_needed_for_sector_ownership integer DEFAULT 5,
    
    -- Economy Settings
    igb_enabled boolean DEFAULT true,
    igb_interest_rate_per_update numeric(10,6) DEFAULT 0.05,
    igb_loan_rate_per_update numeric(10,6) DEFAULT 0.1,
    planet_interest_rate numeric(10,6) DEFAULT 0.06,
    
    -- Colonist & Production Settings
    colonists_limit bigint DEFAULT 100000000000,
    colonist_production_rate numeric(10,6) DEFAULT 0.005,
    colonists_per_fighter integer DEFAULT 20000,
    colonists_per_torpedo integer DEFAULT 8000,
    colonists_per_ore integer DEFAULT 800,
    colonists_per_organics integer DEFAULT 400,
    colonists_per_goods integer DEFAULT 800,
    colonists_per_energy integer DEFAULT 400,
    colonists_per_credits integer DEFAULT 67,
    
    -- Player Limits
    max_accumulated_turns integer DEFAULT 5000,
    max_traderoutes_per_player integer DEFAULT 40,
    
    -- Combat & Defense Settings
    energy_per_sector_fighter numeric(10,3) DEFAULT 0.1,
    sector_fighter_degradation_rate numeric(10,3) DEFAULT 5.0,
    
    -- Scheduler Settings (in minutes)
    tick_interval_minutes integer DEFAULT 6,
    turns_generation_interval_minutes integer DEFAULT 3,
    turns_per_generation integer DEFAULT 12,
    defenses_check_interval_minutes integer DEFAULT 3,
    xenobes_play_interval_minutes integer DEFAULT 3,
    igb_interest_accumulation_interval_minutes integer DEFAULT 2,
    news_generation_interval_minutes integer DEFAULT 6,
    planet_production_interval_minutes integer DEFAULT 2,
    port_regeneration_interval_minutes integer DEFAULT 1,
    ships_tow_from_fed_sectors_interval_minutes integer DEFAULT 3,
    rankings_generation_interval_minutes integer DEFAULT 1,
    sector_defenses_degrade_interval_minutes integer DEFAULT 6,
    planetary_apocalypse_interval_minutes integer DEFAULT 60,
    
    -- Advanced Settings
    use_new_planet_update_code boolean DEFAULT true,
    limit_captured_planets_max_credits boolean DEFAULT false,
    captured_planets_max_credits bigint DEFAULT 1000000000,
    
    -- Metadata
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    updated_by uuid REFERENCES auth.users(id),
    
    -- Constraints
    CONSTRAINT universe_settings_unique_per_universe UNIQUE (universe_id),
    CONSTRAINT universe_settings_positive_sectors CHECK (number_of_sectors > 0),
    CONSTRAINT universe_settings_positive_links CHECK (max_links_per_sector > 0),
    CONSTRAINT universe_settings_valid_tech_levels CHECK (
        avg_tech_level_mines > 0 AND 
        avg_tech_emergency_warp_degrade > 0 AND 
        max_avg_tech_federation_sectors > 0
    ),
    CONSTRAINT universe_settings_valid_rates CHECK (
        igb_interest_rate_per_update >= 0 AND 
        igb_loan_rate_per_update >= 0 AND 
        planet_interest_rate >= 0 AND 
        colonist_production_rate >= 0
    ),
    CONSTRAINT universe_settings_positive_limits CHECK (
        colonists_limit > 0 AND 
        max_accumulated_turns > 0 AND 
        max_traderoutes_per_player > 0
    ),
    CONSTRAINT universe_settings_positive_intervals CHECK (
        tick_interval_minutes > 0 AND 
        turns_generation_interval_minutes > 0 AND 
        turns_per_generation > 0
    )
);

-- Add indexes for performance
CREATE INDEX idx_universe_settings_universe_id ON public.universe_settings(universe_id);
CREATE INDEX idx_universe_settings_created_at ON public.universe_settings(created_at);

-- Enable RLS
ALTER TABLE public.universe_settings ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Universe settings are viewable by everyone" ON public.universe_settings
    FOR SELECT USING (true);

CREATE POLICY "Only admins can modify universe settings" ON public.universe_settings
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles 
            WHERE user_id = auth.uid() AND is_admin = true
        )
    );

-- Function to get universe settings with defaults
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
    captured_planets_max_credits bigint
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
        us.captured_planets_max_credits
    FROM public.universe_settings us
    WHERE us.universe_id = p_universe_id;
    
    -- If no settings found, return defaults (this shouldn't happen in normal operation)
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
            1000000000::bigint;
    END IF;
END;
$$;

-- Function to create default settings for a new universe
CREATE OR REPLACE FUNCTION public.create_universe_default_settings(p_universe_id uuid, p_created_by uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_settings_id uuid;
BEGIN
    INSERT INTO public.universe_settings (
        universe_id,
        created_by,
        updated_by
    ) VALUES (
        p_universe_id,
        p_created_by,
        p_created_by
    ) RETURNING id INTO v_settings_id;
    
    RETURN v_settings_id;
END;
$$;

-- Function to update universe settings
CREATE OR REPLACE FUNCTION public.update_universe_settings(
    p_universe_id uuid,
    p_settings jsonb,
    p_updated_by uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_updated boolean := false;
BEGIN
    -- Check if user is admin
    IF NOT EXISTS (
        SELECT 1 FROM public.user_profiles 
        WHERE user_id = p_updated_by AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Access denied. Admin privileges required.';
    END IF;
    
    -- Update settings
    UPDATE public.universe_settings 
    SET 
        game_version = COALESCE((p_settings->>'game_version')::text, game_version),
        game_name = COALESCE((p_settings->>'game_name')::text, game_name),
        avg_tech_level_mines = COALESCE((p_settings->>'avg_tech_level_mines')::integer, avg_tech_level_mines),
        avg_tech_emergency_warp_degrade = COALESCE((p_settings->>'avg_tech_emergency_warp_degrade')::integer, avg_tech_emergency_warp_degrade),
        max_avg_tech_federation_sectors = COALESCE((p_settings->>'max_avg_tech_federation_sectors')::integer, max_avg_tech_federation_sectors),
        tech_level_upgrade_bases = COALESCE((p_settings->>'tech_level_upgrade_bases')::integer, tech_level_upgrade_bases),
        number_of_sectors = COALESCE((p_settings->>'number_of_sectors')::integer, number_of_sectors),
        max_links_per_sector = COALESCE((p_settings->>'max_links_per_sector')::integer, max_links_per_sector),
        max_planets_per_sector = COALESCE((p_settings->>'max_planets_per_sector')::integer, max_planets_per_sector),
        planets_needed_for_sector_ownership = COALESCE((p_settings->>'planets_needed_for_sector_ownership')::integer, planets_needed_for_sector_ownership),
        igb_enabled = COALESCE((p_settings->>'igb_enabled')::boolean, igb_enabled),
        igb_interest_rate_per_update = COALESCE((p_settings->>'igb_interest_rate_per_update')::numeric, igb_interest_rate_per_update),
        igb_loan_rate_per_update = COALESCE((p_settings->>'igb_loan_rate_per_update')::numeric, igb_loan_rate_per_update),
        planet_interest_rate = COALESCE((p_settings->>'planet_interest_rate')::numeric, planet_interest_rate),
        colonists_limit = COALESCE((p_settings->>'colonists_limit')::bigint, colonists_limit),
        colonist_production_rate = COALESCE((p_settings->>'colonist_production_rate')::numeric, colonist_production_rate),
        colonists_per_fighter = COALESCE((p_settings->>'colonists_per_fighter')::integer, colonists_per_fighter),
        colonists_per_torpedo = COALESCE((p_settings->>'colonists_per_torpedo')::integer, colonists_per_torpedo),
        colonists_per_ore = COALESCE((p_settings->>'colonists_per_ore')::integer, colonists_per_ore),
        colonists_per_organics = COALESCE((p_settings->>'colonists_per_organics')::integer, colonists_per_organics),
        colonists_per_goods = COALESCE((p_settings->>'colonists_per_goods')::integer, colonists_per_goods),
        colonists_per_energy = COALESCE((p_settings->>'colonists_per_energy')::integer, colonists_per_energy),
        colonists_per_credits = COALESCE((p_settings->>'colonists_per_credits')::integer, colonists_per_credits),
        max_accumulated_turns = COALESCE((p_settings->>'max_accumulated_turns')::integer, max_accumulated_turns),
        max_traderoutes_per_player = COALESCE((p_settings->>'max_traderoutes_per_player')::integer, max_traderoutes_per_player),
        energy_per_sector_fighter = COALESCE((p_settings->>'energy_per_sector_fighter')::numeric, energy_per_sector_fighter),
        sector_fighter_degradation_rate = COALESCE((p_settings->>'sector_fighter_degradation_rate')::numeric, sector_fighter_degradation_rate),
        tick_interval_minutes = COALESCE((p_settings->>'tick_interval_minutes')::integer, tick_interval_minutes),
        turns_generation_interval_minutes = COALESCE((p_settings->>'turns_generation_interval_minutes')::integer, turns_generation_interval_minutes),
        turns_per_generation = COALESCE((p_settings->>'turns_per_generation')::integer, turns_per_generation),
        defenses_check_interval_minutes = COALESCE((p_settings->>'defenses_check_interval_minutes')::integer, defenses_check_interval_minutes),
        xenobes_play_interval_minutes = COALESCE((p_settings->>'xenobes_play_interval_minutes')::integer, xenobes_play_interval_minutes),
        igb_interest_accumulation_interval_minutes = COALESCE((p_settings->>'igb_interest_accumulation_interval_minutes')::integer, igb_interest_accumulation_interval_minutes),
        news_generation_interval_minutes = COALESCE((p_settings->>'news_generation_interval_minutes')::integer, news_generation_interval_minutes),
        planet_production_interval_minutes = COALESCE((p_settings->>'planet_production_interval_minutes')::integer, planet_production_interval_minutes),
        port_regeneration_interval_minutes = COALESCE((p_settings->>'port_regeneration_interval_minutes')::integer, port_regeneration_interval_minutes),
        ships_tow_from_fed_sectors_interval_minutes = COALESCE((p_settings->>'ships_tow_from_fed_sectors_interval_minutes')::integer, ships_tow_from_fed_sectors_interval_minutes),
        rankings_generation_interval_minutes = COALESCE((p_settings->>'rankings_generation_interval_minutes')::integer, rankings_generation_interval_minutes),
        sector_defenses_degrade_interval_minutes = COALESCE((p_settings->>'sector_defenses_degrade_interval_minutes')::integer, sector_defenses_degrade_interval_minutes),
        planetary_apocalypse_interval_minutes = COALESCE((p_settings->>'planetary_apocalypse_interval_minutes')::integer, planetary_apocalypse_interval_minutes),
        use_new_planet_update_code = COALESCE((p_settings->>'use_new_planet_update_code')::boolean, use_new_planet_update_code),
        limit_captured_planets_max_credits = COALESCE((p_settings->>'limit_captured_planets_max_credits')::boolean, limit_captured_planets_max_credits),
        captured_planets_max_credits = COALESCE((p_settings->>'captured_planets_max_credits')::bigint, captured_planets_max_credits),
        updated_at = now(),
        updated_by = p_updated_by
    WHERE universe_id = p_universe_id;
    
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated > 0;
END;
$$;

-- Grant permissions
GRANT SELECT ON public.universe_settings TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_universe_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_universe_default_settings(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_universe_settings(uuid, jsonb, uuid) TO authenticated;

-- Set ownership
ALTER TABLE public.universe_settings OWNER TO postgres;
ALTER FUNCTION public.get_universe_settings(uuid) OWNER TO postgres;
ALTER FUNCTION public.create_universe_default_settings(uuid, uuid) OWNER TO postgres;
ALTER FUNCTION public.update_universe_settings(uuid, jsonb, uuid) OWNER TO postgres;
