-- Fix armor level inconsistency
-- Ships with armor points but armor_lvl = 0 need to have their armor_lvl set properly

-- armor_lvl = tech level (like computer_lvl) that determines capacity
-- armor = current armor points (like fighters) that can be bought/sold
-- armor_max = calculated capacity based on armor_lvl

-- For ships with armor > 0 but armor_lvl = 0, set armor_lvl to support their current armor
-- Using BNT capacity formula: 100 * (1.5^(armor_lvl-1))

UPDATE ships 
SET armor_lvl = CASE 
  WHEN armor <= 0 THEN 0
  WHEN armor <= 100 THEN 1      -- 100 * 1.5^0 = 100
  WHEN armor <= 150 THEN 2      -- 100 * 1.5^1 = 150  
  WHEN armor <= 225 THEN 3      -- 100 * 1.5^2 = 225
  WHEN armor <= 337 THEN 4      -- 100 * 1.5^3 = 337
  WHEN armor <= 506 THEN 5      -- 100 * 1.5^4 = 506
  WHEN armor <= 759 THEN 6      -- 100 * 1.5^5 = 759
  WHEN armor <= 1139 THEN 7     -- 100 * 1.5^6 = 1139
  WHEN armor <= 1708 THEN 8     -- 100 * 1.5^7 = 1708
  WHEN armor <= 2562 THEN 9     -- 100 * 1.5^8 = 2562
  WHEN armor <= 3843 THEN 10    -- 100 * 1.5^9 = 3843
  WHEN armor <= 5765 THEN 11    -- 100 * 1.5^10 = 5765
  WHEN armor <= 8650 THEN 12    -- 100 * 1.5^11 = 8650 (rounded)
  WHEN armor <= 12971 THEN 13   -- 100 * 1.5^12 = 12971
  WHEN armor <= 19456 THEN 14   -- 100 * 1.5^13 = 19456
  WHEN armor <= 29184 THEN 15   -- 100 * 1.5^14 = 29184
  ELSE CEIL(LOG(armor::numeric/100) / LOG(1.5) + 1)::integer
END
WHERE armor_lvl = 0 AND armor > 0;

-- Update armor_max to match the calculated armor_lvl
UPDATE ships 
SET armor_max = (100 * POWER(1.5, armor_lvl - 1))::integer
WHERE armor_lvl > 0;
