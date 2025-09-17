-- Stock dynamics and dynamic pricing functions
-- Run once in Supabase SQL Editor

-- Function to calculate dynamic price multiplier based on stock
CREATE OR REPLACE FUNCTION calculate_price_multiplier(
  current_stock INTEGER,
  base_stock INTEGER DEFAULT 1000000000
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- Price range: 0.8x to 1.5x based on stock levels
  -- Low stock = higher prices, high stock = lower prices
  -- Use logarithmic scaling to make small changes negligible for low-level players
  
  IF current_stock <= 0 THEN
    RETURN 1.5; -- Maximum price when out of stock
  END IF;
  
  -- Logarithmic scaling: log10(stock/base_stock)
  -- This means 10% stock = ~1.4x price, 50% stock = ~1.0x price, 200% stock = ~0.8x price
  DECLARE
    stock_ratio NUMERIC := current_stock::NUMERIC / base_stock;
    log_factor NUMERIC := LOG(10, GREATEST(stock_ratio, 0.1)); -- Clamp to avoid log(0)
    multiplier NUMERIC;
  BEGIN
    -- Scale log factor to price range (0.8 to 1.5)
    multiplier := 1.5 - (log_factor + 1) * 0.35; -- log(0.1) ≈ -1, log(10) ≈ 1
    multiplier := GREATEST(0.8, LEAST(1.5, multiplier)); -- Clamp to range
    RETURN multiplier;
  END;
END;
$$;

-- Function to update port stock dynamics (called by cron)
CREATE OR REPLACE FUNCTION update_port_stock_dynamics()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  port_record RECORD;
  updated_count INTEGER := 0;
  decay_rate NUMERIC := 0.05; -- 5% decay
  regen_rate NUMERIC := 0.10; -- 10% regeneration
  base_stock INTEGER := 1000000000;
BEGIN
  -- Process each commodity port
  FOR port_record IN 
    SELECT id, kind, ore, organics, goods, energy
    FROM ports 
    WHERE kind IN ('ore', 'organics', 'goods', 'energy')
  LOOP
    -- Decay non-native stock (5% loss)
    -- Regenerate native stock (10% gain toward base_stock)
    UPDATE ports SET
      ore = CASE 
        WHEN port_record.kind = 'ore' THEN 
          LEAST(base_stock, port_record.ore + FLOOR((base_stock - port_record.ore) * regen_rate))
        ELSE 
          GREATEST(0, port_record.ore - FLOOR(port_record.ore * decay_rate))
      END,
      organics = CASE 
        WHEN port_record.kind = 'organics' THEN 
          LEAST(base_stock, port_record.organics + FLOOR((base_stock - port_record.organics) * regen_rate))
        ELSE 
          GREATEST(0, port_record.organics - FLOOR(port_record.organics * decay_rate))
      END,
      goods = CASE 
        WHEN port_record.kind = 'goods' THEN 
          LEAST(base_stock, port_record.goods + FLOOR((base_stock - port_record.goods) * regen_rate))
        ELSE 
          GREATEST(0, port_record.goods - FLOOR(port_record.goods * decay_rate))
      END,
      energy = CASE 
        WHEN port_record.kind = 'energy' THEN 
          LEAST(base_stock, port_record.energy + FLOOR((base_stock - port_record.energy) * regen_rate))
        ELSE 
          GREATEST(0, port_record.energy - FLOOR(port_record.energy * decay_rate))
      END
    WHERE id = port_record.id;
    
    updated_count := updated_count + 1;
  END LOOP;
  
  RETURN updated_count;
END;
$$;
