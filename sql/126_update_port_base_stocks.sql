-- Update Port Base Stocks to Match Live BNT (100M instead of 1B)
-- Run once in Supabase SQL Editor

-- ============================================================================
-- 1. UPDATE ALL PORTS TO CORRECT BASE STOCK AMOUNTS
-- ============================================================================

-- Update Ore ports to 100M base stock
UPDATE ports 
SET ore = 100000000
WHERE kind = 'ore';

-- Update Organics ports to 100M base stock  
UPDATE ports 
SET organics = 100000000
WHERE kind = 'organics';

-- Update Goods ports to 100M base stock
UPDATE ports 
SET goods = 100000000
WHERE kind = 'goods';

-- Update Energy ports to 1B base stock (Energy ports keep 1B as per live BNT)
UPDATE ports 
SET energy = 1000000000
WHERE kind = 'energy';

-- ============================================================================
-- 2. UPDATE ENHANCED PRICING FUNCTION BASE STOCKS
-- ============================================================================

-- Drop and recreate the pricing function with correct base stocks
DROP FUNCTION IF EXISTS calculate_price_multiplier(INTEGER, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION calculate_price_multiplier(
  current_stock INTEGER,
  port_kind TEXT DEFAULT 'ore',
  base_stock INTEGER DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_base_stock INTEGER;
  stock_ratio NUMERIC;
  log_factor NUMERIC;
  multiplier NUMERIC;
BEGIN
  -- Set port-type-specific base stock levels (matching live BNT screenshots)
  IF base_stock IS NULL THEN
    CASE port_kind
      WHEN 'ore' THEN v_base_stock := 100000000;      -- 100M (matches live BNT)
      WHEN 'organics' THEN v_base_stock := 100000000; -- 100M (matches live BNT)
      WHEN 'goods' THEN v_base_stock := 100000000;     -- 100M (matches live BNT)
      WHEN 'energy' THEN v_base_stock := 1000000000;   -- 1B (matches live BNT)
      ELSE v_base_stock := 100000000;                  -- Default to 100M
    END CASE;
  ELSE
    v_base_stock := base_stock;
  END IF;
  
  -- Handle depleted stock (maximum price spike)
  IF current_stock <= 0 THEN
    RETURN 2.0; -- 200% of base price when completely out of stock
  END IF;
  
  -- Calculate stock ratio
  stock_ratio := current_stock::NUMERIC / v_base_stock;
  
  -- Enhanced logarithmic scaling for more dramatic price fluctuations
  -- This creates more meaningful price changes that encourage exploration
  log_factor := LOG(10, GREATEST(stock_ratio, 0.05)); -- Clamp to avoid log(0)
  
  -- Scale log factor to enhanced price range (0.5x to 2.0x)
  -- Stock levels: 0.05x = 2.0x price, 0.5x = 1.2x price, 1.0x = 1.0x price, 2.0x = 0.8x price, 10x = 0.5x price
  multiplier := 2.0 - (log_factor + 1.3) * 0.75; -- Adjusted scaling for better curve
  
  -- Clamp to enhanced range
  multiplier := GREATEST(0.5, LEAST(2.0, multiplier));
  
  RETURN multiplier;
END;
$$;

-- ============================================================================
-- 3. UPDATE STOCK DYNAMICS FUNCTION BASE STOCKS
-- ============================================================================

-- Drop and recreate the stock dynamics function with correct base stocks
DROP FUNCTION IF EXISTS update_port_stock_dynamics();

CREATE OR REPLACE FUNCTION update_port_stock_dynamics()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  port_record RECORD;
  updated_count INTEGER := 0;
  decay_rate NUMERIC := 0.05; -- 5% decay for non-native commodities
  regen_rate NUMERIC := 0.10; -- 10% regeneration for native commodities
  native_stock INTEGER;
  native_cap INTEGER;
BEGIN
  -- Process each commodity port
  FOR port_record IN 
    SELECT * FROM ports WHERE kind IN ('ore', 'organics', 'goods', 'energy')
  LOOP
    -- Get port-type-specific base stock and cap
    CASE port_record.kind
      WHEN 'ore' THEN 
        native_stock := port_record.ore;
        native_cap := 100000000; -- 100M cap
      WHEN 'organics' THEN 
        native_stock := port_record.organics;
        native_cap := 100000000; -- 100M cap
      WHEN 'goods' THEN 
        native_stock := port_record.goods;
        native_cap := 100000000; -- 100M cap
      WHEN 'energy' THEN 
        native_stock := port_record.energy;
        native_cap := 1000000000; -- 1B cap
    END CASE;
    
    -- Update native commodity (regeneration towards cap)
    IF native_stock < native_cap THEN
      CASE port_record.kind
        WHEN 'ore' THEN
          UPDATE ports 
          SET ore = LEAST(native_cap, native_stock + (native_cap - native_stock) * regen_rate)
          WHERE id = port_record.id;
        WHEN 'organics' THEN
          UPDATE ports 
          SET organics = LEAST(native_cap, native_stock + (native_cap - native_stock) * regen_rate)
          WHERE id = port_record.id;
        WHEN 'goods' THEN
          UPDATE ports 
          SET goods = LEAST(native_cap, native_stock + (native_cap - native_stock) * regen_rate)
          WHERE id = port_record.id;
        WHEN 'energy' THEN
          UPDATE ports 
          SET energy = LEAST(native_cap, native_stock + (native_cap - native_stock) * regen_rate)
          WHERE id = port_record.id;
      END CASE;
    END IF;
    
    -- Decay non-native commodities (but don't go below 0)
    UPDATE ports 
    SET 
      ore = CASE WHEN port_record.kind != 'ore' THEN GREATEST(0, ore - (ore * decay_rate)) ELSE ore END,
      organics = CASE WHEN port_record.kind != 'organics' THEN GREATEST(0, organics - (organics * decay_rate)) ELSE organics END,
      goods = CASE WHEN port_record.kind != 'goods' THEN GREATEST(0, goods - (goods * decay_rate)) ELSE goods END,
      energy = CASE WHEN port_record.kind != 'energy' THEN GREATEST(0, energy - (energy * decay_rate)) ELSE energy END
    WHERE id = port_record.id;
    
    updated_count := updated_count + 1;
  END LOOP;
  
  RETURN updated_count;
END;
$$;

-- ============================================================================
-- 4. VERIFICATION QUERIES
-- ============================================================================

-- Check port stock distribution by type
SELECT 
  kind,
  COUNT(*) as port_count,
  AVG(ore) as avg_ore_stock,
  AVG(organics) as avg_organics_stock,
  AVG(goods) as avg_goods_stock,
  AVG(energy) as avg_energy_stock
FROM ports 
WHERE kind != 'special'
GROUP BY kind
ORDER BY kind;

-- Test the updated pricing function
SELECT 
  'Test Updated Pricing' as test_name,
  calculate_price_multiplier(50000000, 'ore') as low_stock_multiplier,
  calculate_price_multiplier(100000000, 'ore') as normal_stock_multiplier,
  calculate_price_multiplier(200000000, 'ore') as high_stock_multiplier,
  calculate_price_multiplier(500000000, 'energy') as energy_low_stock_multiplier,
  calculate_price_multiplier(1000000000, 'energy') as energy_normal_stock_multiplier;
