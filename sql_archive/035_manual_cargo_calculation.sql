-- Alternative approach: Calculate cargo manually in the upgrade function
-- Instead of relying on generated columns, calculate cargo directly

DO $$
BEGIN
  -- Drop the generated cargo column
  ALTER TABLE ships DROP COLUMN IF EXISTS cargo;
  
  -- Add cargo as a regular column
  ALTER TABLE ships ADD COLUMN cargo INTEGER DEFAULT 1000;
  
  -- Update existing ships with correct cargo values
  UPDATE ships SET cargo = CASE 
    WHEN hull_lvl = 1 THEN 1000
    WHEN hull_lvl = 2 THEN 3500
    WHEN hull_lvl = 3 THEN 7224
    WHEN hull_lvl = 4 THEN 10000
    WHEN hull_lvl = 5 THEN 13162
    ELSE FLOOR(1000 * POWER(hull_lvl, 1.8))
  END;
  
  RAISE NOTICE 'Cargo column converted to regular column with manual calculation';
END $$;
