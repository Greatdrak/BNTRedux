-- Fix Ship Max Columns Consistency
-- This migration removes inconsistent stored max columns and replaces them with generated columns
-- using the BNT capacity formula: 100 * (1.5^(tech_level-1))

-- Step 1: Remove inconsistent stored max columns
ALTER TABLE ships DROP COLUMN IF EXISTS hull_max;
ALTER TABLE ships DROP COLUMN IF EXISTS armor_max; 
ALTER TABLE ships DROP COLUMN IF EXISTS energy_max;
ALTER TABLE ships DROP COLUMN IF EXISTS shield_max; -- Remove entirely (shields are combat-calculated)

-- Step 2: Add consistent generated columns using BNT formula
ALTER TABLE ships ADD COLUMN hull_max INTEGER GENERATED ALWAYS AS (100 * POWER(1.5, hull_lvl - 1)) STORED;
ALTER TABLE ships ADD COLUMN armor_max INTEGER GENERATED ALWAYS AS (100 * POWER(1.5, armor_lvl - 1)) STORED;
ALTER TABLE ships ADD COLUMN energy_max INTEGER GENERATED ALWAYS AS (100 * POWER(1.5, power_lvl - 1)) STORED;

-- Step 3: Fix any existing ships that have values exceeding their new max
-- (This must be done BEFORE adding constraints)
UPDATE ships SET hull = hull_max WHERE hull > hull_max;
UPDATE ships SET armor = armor_max WHERE armor > armor_max;
UPDATE ships SET energy = energy_max WHERE energy > energy_max;

-- Step 4: Drop existing constraints if they exist, then add new ones
-- (This prevents "constraint already exists" errors)
ALTER TABLE ships DROP CONSTRAINT IF EXISTS ships_hull_range;
ALTER TABLE ships DROP CONSTRAINT IF EXISTS ships_armor_range;
ALTER TABLE ships DROP CONSTRAINT IF EXISTS ships_energy_range;

-- Step 5: Add constraints to ensure current values don't exceed new max values
-- (This will prevent any future ships from having invalid values)
ALTER TABLE ships ADD CONSTRAINT ships_hull_range CHECK (hull >= 0 AND hull <= hull_max);
ALTER TABLE ships ADD CONSTRAINT ships_armor_range CHECK (armor >= 0 AND armor <= armor_max);
ALTER TABLE ships ADD CONSTRAINT ships_energy_range CHECK (energy >= 0 AND energy <= energy_max);

-- Verify the changes
SELECT 
    'Migration completed successfully' as status,
    COUNT(*) as total_ships,
    COUNT(CASE WHEN hull > hull_max THEN 1 END) as hull_violations,
    COUNT(CASE WHEN armor > armor_max THEN 1 END) as armor_violations,
    COUNT(CASE WHEN energy > energy_max THEN 1 END) as energy_violations
FROM ships;
