-- Ship Attributes Extension
-- Adds comprehensive ship attributes for detailed ship management

-- Add new ship attributes
ALTER TABLE ships ADD COLUMN IF NOT EXISTS hull_lvl INTEGER DEFAULT 1;
ALTER TABLE ships ADD COLUMN IF NOT EXISTS hull_max INTEGER GENERATED ALWAYS AS (100 * GREATEST(hull_lvl, 1)) STORED;
ALTER TABLE ships ADD COLUMN IF NOT EXISTS shield_lvl INTEGER DEFAULT 0;
ALTER TABLE ships ADD COLUMN IF NOT EXISTS shield_max INTEGER GENERATED ALWAYS AS (20 * GREATEST(shield_lvl, 0)) STORED;
ALTER TABLE ships ADD COLUMN IF NOT EXISTS comp_lvl INTEGER DEFAULT 1;
ALTER TABLE ships ADD COLUMN IF NOT EXISTS sensor_lvl INTEGER DEFAULT 1;
ALTER TABLE ships ADD COLUMN IF NOT EXISTS engine_lvl INTEGER DEFAULT 1;
ALTER TABLE ships ADD COLUMN IF NOT EXISTS cargo INTEGER GENERATED ALWAYS AS (
  CASE 
    WHEN hull_lvl = 1 THEN 1000
    WHEN hull_lvl = 2 THEN 3500
    ELSE FLOOR(1000 * POWER(hull_lvl, 1.8))
  END
) STORED;
ALTER TABLE ships ADD COLUMN IF NOT EXISTS fighters INTEGER DEFAULT 0;
ALTER TABLE ships ADD COLUMN IF NOT EXISTS torpedoes INTEGER DEFAULT 0;

-- Backfill existing ships with defaults
UPDATE ships SET 
  hull_lvl = COALESCE(hull_lvl, 1),
  shield_lvl = COALESCE(shield_lvl, 0),
  comp_lvl = COALESCE(comp_lvl, 1),
  sensor_lvl = COALESCE(sensor_lvl, 1),
  engine_lvl = COALESCE(engine_lvl, 1),
  fighters = COALESCE(fighters, 0),
  torpedoes = COALESCE(torpedoes, 0)
WHERE hull_lvl IS NULL OR shield_lvl IS NULL OR comp_lvl IS NULL OR sensor_lvl IS NULL OR engine_lvl IS NULL OR fighters IS NULL OR torpedoes IS NULL;

-- Clamp hull to hull_max
UPDATE ships SET hull = LEAST(hull, hull_max) WHERE hull > hull_max;

-- Clamp shield to shield_max
UPDATE ships SET shield = LEAST(shield, shield_max) WHERE shield > shield_max;

-- Add constraints (drop first if they exist)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_hull_range') THEN
    ALTER TABLE ships DROP CONSTRAINT ships_hull_range;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_shield_range') THEN
    ALTER TABLE ships DROP CONSTRAINT ships_shield_range;
  END IF;
END $$;

ALTER TABLE ships ADD CONSTRAINT ships_hull_range CHECK (hull BETWEEN 0 AND hull_max);
ALTER TABLE ships ADD CONSTRAINT ships_shield_range CHECK (shield BETWEEN 0 AND shield_max);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_ships_player_id ON ships(player_id);

-- Add name column if it doesn't exist
ALTER TABLE ships ADD COLUMN IF NOT EXISTS name TEXT DEFAULT 'Ship';

-- Update existing ships with default name
UPDATE ships SET name = 'Ship' WHERE name IS NULL OR name = '';
