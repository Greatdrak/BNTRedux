-- Ship Capacity System Enhancement
-- Adds proper capacity calculations based on ship levels and infrastructure for special port purchases

-- First, ensure all required ship columns exist with proper defaults
ALTER TABLE public.ships 
ADD COLUMN IF NOT EXISTS armor integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS armor_max integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS power_lvl integer DEFAULT 1,
ADD COLUMN IF NOT EXISTS beam_lvl integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS torp_launcher_lvl integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS cloak_lvl integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS colonists integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS energy integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS energy_max integer DEFAULT 0;

-- Add device columns if they don't exist
ALTER TABLE public.ships 
ADD COLUMN IF NOT EXISTS device_space_beacons integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS device_warp_editors integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS device_genesis_torpedoes integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS device_mine_deflectors integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS device_emergency_warp boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS device_escape_pod boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS device_fuel_scoop boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS device_last_seen boolean DEFAULT false;

-- Add colonists to inventories if not exists
ALTER TABLE public.inventories 
ADD COLUMN IF NOT EXISTS colonists integer DEFAULT 0;

-- Create computed columns for ship capacity based on levels
-- These will be calculated by RPC functions rather than stored columns for flexibility

-- Add constraints for new columns
DO $$
BEGIN
    -- Drop existing constraints if they exist
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_armor_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_armor_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_colonists_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_colonists_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_energy_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_energy_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_fighters_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_fighters_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_torpedoes_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_torpedoes_range;
    END IF;
END $$;

-- Add constraints for ship capacity limits
ALTER TABLE public.ships 
ADD CONSTRAINT ships_armor_range CHECK (armor >= 0 AND armor <= armor_max),
ADD CONSTRAINT ships_colonists_range CHECK (colonists >= 0),
ADD CONSTRAINT ships_energy_range CHECK (energy >= 0 AND energy <= energy_max),
ADD CONSTRAINT ships_fighters_range CHECK (fighters >= 0),
ADD CONSTRAINT ships_torpedoes_range CHECK (torpedoes >= 0);

-- Add constraints for device quantities
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_device_space_beacons_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_device_space_beacons_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_device_warp_editors_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_device_warp_editors_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_device_genesis_torpedoes_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_device_genesis_torpedoes_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_device_mine_deflectors_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_device_mine_deflectors_range;
    END IF;
END $$;

ALTER TABLE public.ships 
ADD CONSTRAINT ships_device_space_beacons_range CHECK (device_space_beacons >= 0),
ADD CONSTRAINT ships_device_warp_editors_range CHECK (device_warp_editors >= 0),
ADD CONSTRAINT ships_device_genesis_torpedoes_range CHECK (device_genesis_torpedoes >= 0),
ADD CONSTRAINT ships_device_mine_deflectors_range CHECK (device_mine_deflectors >= 0);

-- Add constraints for level columns
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_power_lvl_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_power_lvl_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_beam_lvl_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_beam_lvl_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_torp_launcher_lvl_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_torp_launcher_lvl_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_cloak_lvl_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_cloak_lvl_range;
    END IF;
END $$;

ALTER TABLE public.ships 
ADD CONSTRAINT ships_power_lvl_range CHECK (power_lvl >= 0),
ADD CONSTRAINT ships_beam_lvl_range CHECK (beam_lvl >= 0),
ADD CONSTRAINT ships_torp_launcher_lvl_range CHECK (torp_launcher_lvl >= 0),
ADD CONSTRAINT ships_cloak_lvl_range CHECK (cloak_lvl >= 0);

-- Add constraint for colonists in inventories
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'inventories_colonists_range') THEN
        ALTER TABLE public.inventories DROP CONSTRAINT inventories_colonists_range;
    END IF;
END $$;

ALTER TABLE public.inventories 
ADD CONSTRAINT inventories_colonists_range CHECK (colonists >= 0);

-- Backfill existing ships with proper defaults
UPDATE public.ships SET 
  armor = COALESCE(armor, 0),
  armor_max = COALESCE(armor_max, 0),
  power_lvl = COALESCE(power_lvl, 1),
  beam_lvl = COALESCE(beam_lvl, 0),
  torp_launcher_lvl = COALESCE(torp_launcher_lvl, 0),
  cloak_lvl = COALESCE(cloak_lvl, 0),
  colonists = COALESCE(colonists, 0),
  energy = COALESCE(energy, 0),
  energy_max = COALESCE(energy_max, 0),
  device_space_beacons = COALESCE(device_space_beacons, 0),
  device_warp_editors = COALESCE(device_warp_editors, 0),
  device_genesis_torpedoes = COALESCE(device_genesis_torpedoes, 0),
  device_mine_deflectors = COALESCE(device_mine_deflectors, 0),
  device_emergency_warp = COALESCE(device_emergency_warp, false),
  device_escape_pod = COALESCE(device_escape_pod, true),
  device_fuel_scoop = COALESCE(device_fuel_scoop, false),
  device_last_seen = COALESCE(device_last_seen, false)
WHERE armor IS NULL OR power_lvl IS NULL OR colonists IS NULL;

-- Backfill inventories with colonists
UPDATE public.inventories SET 
  colonists = COALESCE(colonists, 0)
WHERE colonists IS NULL;
