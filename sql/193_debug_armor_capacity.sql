-- Debug armor capacity calculation issue
-- The get_ship_capacity function should return 8650 for armor_lvl 12
-- but it's returning 5767 instead

-- Let's check what the function is actually returning
-- and fix the calculation

-- First, let's see what armor_lvl values exist
SELECT id, armor, armor_lvl, armor_max 
FROM ships 
WHERE armor > 0 
ORDER BY armor DESC 
LIMIT 5;

-- The issue might be in the calculate_bnt_capacity function
-- Let's test it directly:
SELECT 
  public.calculate_bnt_capacity(11) as level_12_capacity,  -- should be 8650
  public.calculate_bnt_capacity(10) as level_11_capacity,  -- should be 5765
  public.calculate_bnt_capacity(9) as level_10_capacity;   -- should be 3843

-- If calculate_bnt_capacity is wrong, let's fix it
CREATE OR REPLACE FUNCTION public.calculate_bnt_capacity(tech_level INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- BNT formula: 100 * (1.5^tech_level)
  -- tech_level = armor_lvl - 1
  RETURN (100 * POWER(1.5, tech_level))::INTEGER;
END;
$$;
