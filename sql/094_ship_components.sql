-- Add missing ship components from original BlackNova Traders
-- These are schema-only additions to avoid breaking existing functionality

-- Add armor system to ships
ALTER TABLE public.ships 
ADD COLUMN IF NOT EXISTS armor integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS armor_max integer DEFAULT 0;

-- Add device slots to ships
ALTER TABLE public.ships 
ADD COLUMN IF NOT EXISTS device_space_beacons integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS device_warp_editors integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS device_genesis_torpedoes integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS device_mine_deflectors integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS device_emergency_warp boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS device_escape_pod boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS device_fuel_scoop boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS device_last_seen boolean DEFAULT false;

-- Add colonists to inventories
ALTER TABLE public.inventories 
ADD COLUMN IF NOT EXISTS colonists integer DEFAULT 0;

-- Add additional ship component levels (schema-only)
ALTER TABLE public.ships 
ADD COLUMN IF NOT EXISTS power_lvl integer DEFAULT 1,
ADD COLUMN IF NOT EXISTS beam_lvl integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS torp_launcher_lvl integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS cloak_lvl integer DEFAULT 0;

-- Add constraints for armor (drop first if exists to avoid conflicts)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_armor_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_armor_range;
    END IF;
END $$;

ALTER TABLE public.ships 
ADD CONSTRAINT ships_armor_range 
CHECK ((armor >= 0) AND (armor <= armor_max));

-- Add constraints for device quantities (non-negative)
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

-- Non-negative checks for new level columns
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

-- Add constraint for colonists (non-negative)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'inventories_colonists_range') THEN
        ALTER TABLE public.inventories DROP CONSTRAINT inventories_colonists_range;
    END IF;
END $$;

ALTER TABLE public.inventories 
ADD CONSTRAINT inventories_colonists_range 
CHECK (colonists >= 0);
