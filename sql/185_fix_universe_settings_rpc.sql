-- Fix universe settings RPC functions to resolve schema mismatch

-- Add missing column to universe_settings table that the original function expects
ALTER TABLE universe_settings ADD COLUMN IF NOT EXISTS avg_tech_level_mines INTEGER DEFAULT 5;

-- Drop existing functions if they exist
DROP FUNCTION IF EXISTS get_universe_settings(UUID);
DROP FUNCTION IF EXISTS create_universe_default_settings(UUID, UUID);
DROP FUNCTION IF EXISTS update_universe_settings(UUID, JSONB, UUID);

-- Create get_universe_settings function matching the original signature
CREATE OR REPLACE FUNCTION get_universe_settings(p_universe_id UUID)
RETURNS TABLE (
  universe_id UUID,
  game_version TEXT,
  game_name TEXT,
  avg_tech_level_mines INTEGER,
  avg_tech_emergency_warp_degrade INTEGER,
  max_avg_tech_federation_sectors INTEGER,
  tech_level_upgrade_bases INTEGER,
  number_of_sectors INTEGER,
  max_links_per_sector INTEGER,
  max_planets_per_sector INTEGER,
  planets_needed_for_sector_ownership INTEGER,
  igb_enabled BOOLEAN,
  igb_interest_rate_per_update NUMERIC,
  igb_loan_rate_per_update NUMERIC,
  planet_interest_rate NUMERIC,
  colonists_limit BIGINT,
  colonist_production_rate NUMERIC,
  colonists_per_fighter INTEGER,
  colonists_per_torpedo INTEGER,
  colonists_per_ore INTEGER,
  colonists_per_organics INTEGER,
  colonists_per_goods INTEGER,
  colonists_per_energy INTEGER,
  colonists_per_credits INTEGER,
  max_accumulated_turns INTEGER,
  max_traderoutes_per_player INTEGER,
  energy_per_sector_fighter NUMERIC,
  sector_fighter_degradation_rate NUMERIC,
  tick_interval_minutes INTEGER,
  turns_generation_interval_minutes INTEGER,
  turns_per_generation INTEGER,
  defenses_check_interval_minutes INTEGER,
  xenobes_play_interval_minutes INTEGER,
  igb_interest_accumulation_interval_minutes INTEGER,
  news_generation_interval_minutes INTEGER,
  planet_production_interval_minutes INTEGER,
  port_regeneration_interval_minutes INTEGER,
  ships_tow_from_fed_sectors_interval_minutes INTEGER,
  rankings_generation_interval_minutes INTEGER,
  sector_defenses_degrade_interval_minutes INTEGER,
  planetary_apocalypse_interval_minutes INTEGER,
  use_new_planet_update_code BOOLEAN,
  limit_captured_planets_max_credits BOOLEAN,
  captured_planets_max_credits BIGINT,
  turn_generation_interval_minutes INTEGER,
  cycle_interval_minutes INTEGER,
  update_interval_minutes INTEGER,
  last_turn_generation TIMESTAMPTZ,
  last_cycle_event TIMESTAMPTZ,
  last_update_event TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
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
    us.turn_generation_interval_minutes,
    us.cycle_interval_minutes,
    us.update_interval_minutes,
    us.last_turn_generation,
    us.last_cycle_event,
    us.last_update_event
  FROM universe_settings us
  WHERE us.universe_id = p_universe_id;
END;
$$;

-- Create create_universe_default_settings function
CREATE OR REPLACE FUNCTION create_universe_default_settings(
  p_universe_id UUID,
  p_created_by UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_settings_id UUID;
BEGIN
  INSERT INTO universe_settings (
    universe_id,
    max_accumulated_turns,
    turns_generation_interval_minutes,
    port_regeneration_interval_minutes,
    rankings_generation_interval_minutes,
    defenses_check_interval_minutes,
    xenobes_play_interval_minutes,
    igb_interest_accumulation_interval_minutes,
    news_generation_interval_minutes,
    planet_production_interval_minutes,
    ships_tow_from_fed_sectors_interval_minutes,
    sector_defenses_degrade_interval_minutes,
    planetary_apocalypse_interval_minutes,
    created_by,
    updated_by
  ) VALUES (
    p_universe_id,
    5000, -- max accumulated turns
    3,    -- 3 minutes turn generation
    5,    -- 5 minutes port regeneration
    10,   -- 10 minutes rankings
    15,   -- 15 minutes defenses check
    30,   -- 30 minutes xenobes play
    10,   -- 10 minutes IGB interest
    60,   -- 60 minutes news generation
    15,   -- 15 minutes planet production
    30,   -- 30 minutes ships tow
    60,   -- 60 minutes sector defenses degrade
    1440, -- 1440 minutes planetary apocalypse (24 hours)
    p_created_by,
    p_created_by
  ) RETURNING id INTO v_settings_id;
  
  RETURN v_settings_id;
END;
$$;

-- Create update_universe_settings function
CREATE OR REPLACE FUNCTION update_universe_settings(
  p_universe_id UUID,
  p_settings JSONB,
  p_updated_by UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE universe_settings SET
    game_version = COALESCE((p_settings->>'game_version')::TEXT, game_version),
    game_name = COALESCE((p_settings->>'game_name')::TEXT, game_name),
    avg_tech_level_mines = COALESCE((p_settings->>'avg_tech_level_mines')::INTEGER, avg_tech_level_mines),
    avg_tech_emergency_warp_degrade = COALESCE((p_settings->>'avg_tech_emergency_warp_degrade')::INTEGER, avg_tech_emergency_warp_degrade),
    max_avg_tech_federation_sectors = COALESCE((p_settings->>'max_avg_tech_federation_sectors')::INTEGER, max_avg_tech_federation_sectors),
    tech_level_upgrade_bases = COALESCE((p_settings->>'tech_level_upgrade_bases')::INTEGER, tech_level_upgrade_bases),
    number_of_sectors = COALESCE((p_settings->>'number_of_sectors')::INTEGER, number_of_sectors),
    max_links_per_sector = COALESCE((p_settings->>'max_links_per_sector')::INTEGER, max_links_per_sector),
    max_planets_per_sector = COALESCE((p_settings->>'max_planets_per_sector')::INTEGER, max_planets_per_sector),
    planets_needed_for_sector_ownership = COALESCE((p_settings->>'planets_needed_for_sector_ownership')::INTEGER, planets_needed_for_sector_ownership),
    igb_enabled = COALESCE((p_settings->>'igb_enabled')::BOOLEAN, igb_enabled),
    igb_interest_rate_per_update = COALESCE((p_settings->>'igb_interest_rate_per_update')::NUMERIC, igb_interest_rate_per_update),
    igb_loan_rate_per_update = COALESCE((p_settings->>'igb_loan_rate_per_update')::NUMERIC, igb_loan_rate_per_update),
    planet_interest_rate = COALESCE((p_settings->>'planet_interest_rate')::NUMERIC, planet_interest_rate),
    colonists_limit = COALESCE((p_settings->>'colonists_limit')::BIGINT, colonists_limit),
    colonist_production_rate = COALESCE((p_settings->>'colonist_production_rate')::NUMERIC, colonist_production_rate),
    colonists_per_fighter = COALESCE((p_settings->>'colonists_per_fighter')::INTEGER, colonists_per_fighter),
    colonists_per_torpedo = COALESCE((p_settings->>'colonists_per_torpedo')::INTEGER, colonists_per_torpedo),
    colonists_per_ore = COALESCE((p_settings->>'colonists_per_ore')::INTEGER, colonists_per_ore),
    colonists_per_organics = COALESCE((p_settings->>'colonists_per_organics')::INTEGER, colonists_per_organics),
    colonists_per_goods = COALESCE((p_settings->>'colonists_per_goods')::INTEGER, colonists_per_goods),
    colonists_per_energy = COALESCE((p_settings->>'colonists_per_energy')::INTEGER, colonists_per_energy),
    colonists_per_credits = COALESCE((p_settings->>'colonists_per_credits')::INTEGER, colonists_per_credits),
    max_accumulated_turns = COALESCE((p_settings->>'max_accumulated_turns')::INTEGER, max_accumulated_turns),
    max_traderoutes_per_player = COALESCE((p_settings->>'max_traderoutes_per_player')::INTEGER, max_traderoutes_per_player),
    energy_per_sector_fighter = COALESCE((p_settings->>'energy_per_sector_fighter')::NUMERIC, energy_per_sector_fighter),
    sector_fighter_degradation_rate = COALESCE((p_settings->>'sector_fighter_degradation_rate')::NUMERIC, sector_fighter_degradation_rate),
    tick_interval_minutes = COALESCE((p_settings->>'tick_interval_minutes')::INTEGER, tick_interval_minutes),
    turns_generation_interval_minutes = COALESCE((p_settings->>'turns_generation_interval_minutes')::INTEGER, turns_generation_interval_minutes),
    turns_per_generation = COALESCE((p_settings->>'turns_per_generation')::INTEGER, turns_per_generation),
    defenses_check_interval_minutes = COALESCE((p_settings->>'defenses_check_interval_minutes')::INTEGER, defenses_check_interval_minutes),
    xenobes_play_interval_minutes = COALESCE((p_settings->>'xenobes_play_interval_minutes')::INTEGER, xenobes_play_interval_minutes),
    igb_interest_accumulation_interval_minutes = COALESCE((p_settings->>'igb_interest_accumulation_interval_minutes')::INTEGER, igb_interest_accumulation_interval_minutes),
    news_generation_interval_minutes = COALESCE((p_settings->>'news_generation_interval_minutes')::INTEGER, news_generation_interval_minutes),
    planet_production_interval_minutes = COALESCE((p_settings->>'planet_production_interval_minutes')::INTEGER, planet_production_interval_minutes),
    port_regeneration_interval_minutes = COALESCE((p_settings->>'port_regeneration_interval_minutes')::INTEGER, port_regeneration_interval_minutes),
    ships_tow_from_fed_sectors_interval_minutes = COALESCE((p_settings->>'ships_tow_from_fed_sectors_interval_minutes')::INTEGER, ships_tow_from_fed_sectors_interval_minutes),
    rankings_generation_interval_minutes = COALESCE((p_settings->>'rankings_generation_interval_minutes')::INTEGER, rankings_generation_interval_minutes),
    sector_defenses_degrade_interval_minutes = COALESCE((p_settings->>'sector_defenses_degrade_interval_minutes')::INTEGER, sector_defenses_degrade_interval_minutes),
    planetary_apocalypse_interval_minutes = COALESCE((p_settings->>'planetary_apocalypse_interval_minutes')::INTEGER, planetary_apocalypse_interval_minutes),
    use_new_planet_update_code = COALESCE((p_settings->>'use_new_planet_update_code')::BOOLEAN, use_new_planet_update_code),
    limit_captured_planets_max_credits = COALESCE((p_settings->>'limit_captured_planets_max_credits')::BOOLEAN, limit_captured_planets_max_credits),
    captured_planets_max_credits = COALESCE((p_settings->>'captured_planets_max_credits')::BIGINT, captured_planets_max_credits),
    updated_by = p_updated_by,
    updated_at = NOW()
  WHERE universe_id = p_universe_id;
  
  RETURN FOUND;
END;
$$;
