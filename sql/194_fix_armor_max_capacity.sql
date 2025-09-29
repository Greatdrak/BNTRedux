-- Fix armor_max capacity for ships with incorrect values
-- This migration recalculates armor_max based on armor_lvl using the BNT capacity formula

-- Fix armor_max to match armor_lvl capacity
UPDATE ships 
SET armor_max = (100 * POWER(1.5, armor_lvl - 1))::integer
WHERE armor_lvl > 0;

-- Verify the fix for the specific ship
SELECT 
    id,
    armor,
    armor_max,
    armor_lvl,
    (100 * POWER(1.5, armor_lvl - 1))::integer as calculated_capacity
FROM ships 
WHERE player_id = '397f60a3-4b79-4252-9e99-8aa3b7f87578';
