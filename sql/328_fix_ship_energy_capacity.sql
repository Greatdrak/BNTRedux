-- Migration: 328_fix_ship_energy_capacity.sql
-- Purpose: Fix energy capacity issues - energy should be separate from cargo

-- First, check if we have energy and energy_max columns
DO $$
BEGIN
  -- Add energy column if it doesn't exist
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name = 'ships' AND column_name = 'energy') THEN
    ALTER TABLE public.ships ADD COLUMN energy integer DEFAULT 0;
  END IF;

  -- Add energy_max as a generated column based on power_lvl
  -- Formula: 100 * (1.5^power_lvl) - BNT capacity formula
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name = 'ships' AND column_name = 'energy_max') THEN
    ALTER TABLE public.ships ADD COLUMN energy_max integer GENERATED ALWAYS AS (
      FLOOR(100 * POWER(1.5, COALESCE(power_lvl, 0)))::integer
    ) STORED;
  END IF;
END $$;

-- Drop the old energy range constraint if it exists
ALTER TABLE public.ships DROP CONSTRAINT IF EXISTS ships_energy_range;

-- Add new energy range constraint that uses energy_max
ALTER TABLE public.ships ADD CONSTRAINT ships_energy_range 
  CHECK (energy >= 0 AND energy <= energy_max);

-- Update any ships that are over capacity
UPDATE public.ships
SET energy = energy_max
WHERE energy > energy_max;

COMMENT ON COLUMN public.ships.energy IS 'Current energy level';
COMMENT ON COLUMN public.ships.energy_max IS 'Maximum energy capacity based on power tech level (100 * 1.5^power_lvl)';

