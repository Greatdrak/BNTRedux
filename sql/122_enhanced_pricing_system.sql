-- Enhanced Pricing System Based on Live BNT Analysis
-- Run once in Supabase SQL Editor

-- ============================================================================
-- 1. UPDATE BASE PRICES TO MATCH LIVE BNT VALUES
-- ============================================================================

-- Update default base prices in ports table to match live BNT analysis
UPDATE ports 
SET 
  price_ore = 15.00,        -- Was 10.00, now matches live BNT (~14-18 range)
  price_organics = 8.00,    -- Was 15.00, now matches live BNT (~7-8 range)  
  price_goods = 22.00,      -- Was 25.00, now matches live BNT (~22-25 range)
  price_energy = 3.00        -- Was 5.00, now matches live BNT (~2-4 range)
WHERE kind != 'special';

-- ============================================================================
-- 2. ENHANCED DYNAMIC PRICING FUNCTION
-- ============================================================================

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS calculate_price_multiplier(INTEGER, INTEGER);

-- Enhanced price multiplier function with port-type-specific base stocks
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
      WHEN 'ore' THEN v_base_stock := 100000000;      -- 100M (matches screenshots)
      WHEN 'organics' THEN v_base_stock := 100000000; -- 100M
      WHEN 'goods' THEN v_base_stock := 100000000;    -- 100M  
      WHEN 'energy' THEN v_base_stock := 1000000000;  -- 1B (matches screenshots)
      ELSE v_base_stock := 100000000;                 -- Default to 100M
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
-- 3. ENHANCED STOCK DYNAMICS FUNCTION
-- ============================================================================

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS update_port_stock_dynamics();

-- Enhanced stock dynamics with port-type-specific regeneration
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
-- 4. UPDATE TRADING FUNCTIONS TO USE ENHANCED PRICING
-- ============================================================================

-- Update the trade_by_type function to use enhanced pricing
CREATE OR REPLACE FUNCTION trade_by_type(
  p_user_id UUID,
  p_port_id UUID,
  p_resource TEXT,
  p_action TEXT,
  p_quantity INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players;
  v_ship ships;
  v_port ports;
  v_sector sectors;
  v_unit_price NUMERIC;
  v_total_cost NUMERIC;
  v_new_credits NUMERIC;
  v_new_cargo INTEGER;
  v_new_stock INTEGER;
  v_result JSONB;
BEGIN
  -- Load player, ship, port with proper universe validation
  SELECT * INTO v_player FROM players WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  SELECT p.* INTO v_port
  FROM ports p
  WHERE p.id = p_port_id FOR UPDATE;
  
  SELECT s.number as sector_number, s.universe_id INTO v_sector
  FROM sectors s
  JOIN ports p ON s.id = p.sector_id
  WHERE p.id = p_port_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Port not found'));
  END IF;

  -- Universe validation
  IF v_player.universe_id != v_sector.universe_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_mismatch', 'message', 'Port not in player universe'));
  END IF;

  -- Validate port type and action
  IF v_port.kind = 'special' THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_port_kind', 'message', 'Special ports do not trade commodities'));
  END IF;

  -- Validate resource
  IF p_resource NOT IN ('ore', 'organics', 'goods', 'energy') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_resource', 'message', 'Invalid resource type'));
  END IF;

  -- Validate action
  IF p_action NOT IN ('buy', 'sell') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_action', 'message', 'Invalid action'));
  END IF;

  -- Validate quantity
  IF p_quantity <= 0 THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_quantity', 'message', 'Quantity must be positive'));
  END IF;

  -- Compute unit price using enhanced dynamic pricing
  DECLARE
    base_price NUMERIC;
    stock_level INTEGER;
    price_multiplier NUMERIC;
  BEGIN
    CASE p_resource
      WHEN 'ore' THEN 
        base_price := v_port.price_ore;
        stock_level := v_port.ore;
      WHEN 'organics' THEN 
        base_price := v_port.price_organics;
        stock_level := v_port.organics;
      WHEN 'goods' THEN 
        base_price := v_port.price_goods;
        stock_level := v_port.goods;
      WHEN 'energy' THEN 
        base_price := v_port.price_energy;
        stock_level := v_port.energy;
    END CASE;
    
    -- Apply enhanced dynamic pricing based on stock levels and port type
    price_multiplier := calculate_price_multiplier(stock_level, v_port.kind);
    v_unit_price := base_price * price_multiplier;
  END;

  -- Apply buy/sell multipliers
  IF p_action = 'buy' THEN
    v_unit_price := v_unit_price * 0.90; -- Player buys at 90% of dynamic price
  ELSE
    v_unit_price := v_unit_price * 1.10; -- Player sells at 110% of dynamic price
  END IF;

  v_total_cost := p_quantity * v_unit_price;

  -- Validate trade constraints
  IF p_action = 'buy' THEN
    -- Can only buy native commodity
    IF p_resource != v_port.kind THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_buy', 'message', 'Can only buy native commodity from this port'));
    END IF;
    
    -- Check stock availability
    CASE p_resource
      WHEN 'ore' THEN v_new_stock := v_port.ore - p_quantity;
      WHEN 'organics' THEN v_new_stock := v_port.organics - p_quantity;
      WHEN 'goods' THEN v_new_stock := v_port.goods - p_quantity;
      WHEN 'energy' THEN v_new_stock := v_port.energy - p_quantity;
    END CASE;
    
    IF v_new_stock < 0 THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_stock', 'message', 'Port does not have enough stock'));
    END IF;
    
    -- Check player credits
    IF v_player.credits < v_total_cost THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
    END IF;
    
    -- Check cargo space
    CASE p_resource
      WHEN 'ore' THEN v_new_cargo := v_ship.ore + p_quantity;
      WHEN 'organics' THEN v_new_cargo := v_ship.organics + p_quantity;
      WHEN 'goods' THEN v_new_cargo := v_ship.goods + p_quantity;
      WHEN 'energy' THEN v_new_cargo := v_ship.energy + p_quantity;
    END CASE;
    
    IF v_new_cargo > v_ship.cargo THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough cargo space'));
    END IF;
    
    v_new_credits := v_player.credits - v_total_cost;
    
  ELSE -- sell
    -- Can only sell non-native commodities
    IF p_resource = v_port.kind THEN
      RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_sell', 'message', 'Cannot sell native commodity to its own port'));
    END IF;
    
    -- Check player stock
    CASE p_resource
      WHEN 'ore' THEN 
        IF v_ship.ore < p_quantity THEN
          RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough ore to sell'));
        END IF;
        v_new_cargo := v_ship.ore - p_quantity;
      WHEN 'organics' THEN 
        IF v_ship.organics < p_quantity THEN
          RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough organics to sell'));
        END IF;
        v_new_cargo := v_ship.organics - p_quantity;
      WHEN 'goods' THEN 
        IF v_ship.goods < p_quantity THEN
          RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough goods to sell'));
        END IF;
        v_new_cargo := v_ship.goods - p_quantity;
      WHEN 'energy' THEN 
        IF v_ship.energy < p_quantity THEN
          RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_cargo', 'message', 'Not enough energy to sell'));
        END IF;
        v_new_cargo := v_ship.energy - p_quantity;
    END CASE;
    
    v_new_credits := v_player.credits + v_total_cost;
    v_new_stock := stock_level + p_quantity; -- Port gains stock when player sells
  END IF;

  -- Execute the trade
  -- Update player credits
  UPDATE players SET credits = v_new_credits WHERE id = v_player.id;
  
  -- Update ship cargo
  CASE p_resource
    WHEN 'ore' THEN
      UPDATE ships SET ore = v_new_cargo WHERE id = v_ship.id;
      UPDATE ports SET ore = v_new_stock WHERE id = v_port.id;
    WHEN 'organics' THEN
      UPDATE ships SET organics = v_new_cargo WHERE id = v_ship.id;
      UPDATE ports SET organics = v_new_stock WHERE id = v_port.id;
    WHEN 'goods' THEN
      UPDATE ships SET goods = v_new_cargo WHERE id = v_ship.id;
      UPDATE ports SET goods = v_new_stock WHERE id = v_port.id;
    WHEN 'energy' THEN
      UPDATE ships SET energy = v_new_cargo WHERE id = v_ship.id;
      UPDATE ports SET energy = v_new_stock WHERE id = v_port.id;
  END CASE;

  -- Return success result
  v_result := jsonb_build_object(
    'success', true,
    'action', p_action,
    'resource', p_resource,
    'quantity', p_quantity,
    'unit_price', v_unit_price,
    'total_cost', v_total_cost,
    'new_credits', v_new_credits,
    'new_cargo', v_new_cargo,
    'new_stock', v_new_stock
  );

  RETURN v_result;
END;
$$;

-- ============================================================================
-- 5. UPDATE AUTO-TRADE FUNCTION TO USE ENHANCED PRICING
-- ============================================================================

-- Update the auto_trade function to use enhanced pricing
CREATE OR REPLACE FUNCTION auto_trade(
  p_user_id UUID,
  p_port_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player players;
  v_ship ships;
  v_port ports;
  v_sector sectors;
  pc text;
  native_price numeric;
  sell_price numeric;
  proceeds numeric;
  total_proceeds numeric := 0;
  trade_summary jsonb := '[]'::jsonb;
  trade_item jsonb;
  err jsonb;
BEGIN
  -- Load player, ship, port with universe validation
  SELECT * INTO v_player FROM players WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Player not found')); END IF;

  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Ship not found')); END IF;

  SELECT p.* INTO v_port
  FROM public.ports p
  WHERE p.id = p_port FOR UPDATE;
  
  SELECT s.number as sector_number, s.universe_id INTO v_sector
  FROM public.sectors s
  JOIN public.ports p ON s.id = p.sector_id
  WHERE p.id = p_port;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Port not found')); END IF;
  IF v_port.kind = 'special' THEN RETURN jsonb_build_object('error', jsonb_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.')); END IF;

  -- Universe validation
  IF v_player.universe_id != v_sector.universe_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'universe_mismatch', 'message', 'Port not in player universe'));
  END IF;

  -- Validate co-location
  IF v_player.current_sector <> v_port.sector_id THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code','wrong_sector','message','Player not in port sector'));
  END IF;

  pc := v_port.kind; -- ore|organics|goods|energy

  -- Enhanced pricing with dynamic stock-based multipliers
  native_price := CASE pc
    WHEN 'ore' THEN v_port.price_ore * calculate_price_multiplier(v_port.ore, v_port.kind)
    WHEN 'organics' THEN v_port.price_organics * calculate_price_multiplier(v_port.organics, v_port.kind)
    WHEN 'goods' THEN v_port.price_goods * calculate_price_multiplier(v_port.goods, v_port.kind)
    WHEN 'energy' THEN v_port.price_energy * calculate_price_multiplier(v_port.energy, v_port.kind)
  END;
  sell_price := native_price * 0.90; -- player buys from port at 0.90 * dynamic price

  -- Compute proceeds from selling all non-native at 1.10 * dynamic price
  FOR trade_item IN
    SELECT 
      resource,
      CASE resource
        WHEN 'ore' THEN v_ship.ore
        WHEN 'organics' THEN v_ship.organics  
        WHEN 'goods' THEN v_ship.goods
        WHEN 'energy' THEN v_ship.energy
      END as qty,
      CASE resource
        WHEN 'ore' THEN v_port.price_ore * calculate_price_multiplier(v_port.ore, v_port.kind) * 1.10
        WHEN 'organics' THEN v_port.price_organics * calculate_price_multiplier(v_port.organics, v_port.kind) * 1.10
        WHEN 'goods' THEN v_port.price_goods * calculate_price_multiplier(v_port.goods, v_port.kind) * 1.10
        WHEN 'energy' THEN v_port.price_energy * calculate_price_multiplier(v_port.energy, v_port.kind) * 1.10
      END as unit_price
    FROM (VALUES ('ore'), ('organics'), ('goods'), ('energy')) t(resource)
    WHERE resource != pc
  LOOP
    IF trade_item->>'qty' IS NOT NULL AND (trade_item->>'qty')::int > 0 THEN
      proceeds := (trade_item->>'qty')::int * (trade_item->>'unit_price')::numeric;
      total_proceeds := total_proceeds + proceeds;
      
      -- Add to trade summary
      trade_summary := trade_summary || jsonb_build_object(
        'action', 'sell',
        'resource', trade_item->>'resource',
        'quantity', trade_item->>'qty',
        'unit_price', trade_item->>'unit_price',
        'total', proceeds
      );
    END IF;
  END LOOP;

  -- Buy maximum native commodity possible
  DECLARE
    max_buy INTEGER;
    buy_cost NUMERIC;
    buy_qty INTEGER;
  BEGIN
    max_buy := LEAST(
      CASE pc
        WHEN 'ore' THEN v_port.ore
        WHEN 'organics' THEN v_port.organics
        WHEN 'goods' THEN v_port.goods
        WHEN 'energy' THEN v_port.energy
      END,
      v_ship.cargo - (
        CASE WHEN pc != 'ore' THEN v_ship.ore ELSE 0 END +
        CASE WHEN pc != 'organics' THEN v_ship.organics ELSE 0 END +
        CASE WHEN pc != 'goods' THEN v_ship.goods ELSE 0 END +
        CASE WHEN pc != 'energy' THEN v_ship.energy ELSE 0 END
      ),
      FLOOR((v_player.credits + total_proceeds) / sell_price)
    );
    
    IF max_buy > 0 THEN
      buy_cost := max_buy * sell_price;
      buy_qty := max_buy;
      
      -- Add to trade summary
      trade_summary := trade_summary || jsonb_build_object(
        'action', 'buy',
        'resource', pc,
        'quantity', buy_qty,
        'unit_price', sell_price,
        'total', buy_cost
      );
    ELSE
      buy_qty := 0;
      buy_cost := 0;
    END IF;
  END;

  -- Execute all trades atomically
  BEGIN
    -- Update player credits
    UPDATE players SET credits = v_player.credits + total_proceeds - buy_cost WHERE id = v_player.id;
    
    -- Clear non-native cargo
    UPDATE ships SET 
      ore = CASE WHEN pc != 'ore' THEN 0 ELSE ore END,
      organics = CASE WHEN pc != 'organics' THEN 0 ELSE organics END,
      goods = CASE WHEN pc != 'goods' THEN 0 ELSE goods END,
      energy = CASE WHEN pc != 'energy' THEN 0 ELSE energy END
    WHERE id = v_ship.id;
    
    -- Add native cargo
    CASE pc
      WHEN 'ore' THEN UPDATE ships SET ore = ore + buy_qty WHERE id = v_ship.id;
      WHEN 'organics' THEN UPDATE ships SET organics = organics + buy_qty WHERE id = v_ship.id;
      WHEN 'goods' THEN UPDATE ships SET goods = goods + buy_qty WHERE id = v_ship.id;
      WHEN 'energy' THEN UPDATE ships SET energy = energy + buy_qty WHERE id = v_ship.id;
    END CASE;
    
    -- Update port stock
    CASE pc
      WHEN 'ore' THEN UPDATE ports SET ore = ore - buy_qty WHERE id = v_port.id;
      WHEN 'organics' THEN UPDATE ports SET organics = organics - buy_qty WHERE id = v_port.id;
      WHEN 'goods' THEN UPDATE ports SET goods = goods - buy_qty WHERE id = v_port.id;
      WHEN 'energy' THEN UPDATE ports SET energy = energy - buy_qty WHERE id = v_port.id;
    END CASE;
    
    -- Add non-native stock to port
    UPDATE ports SET
      ore = ore + CASE WHEN pc != 'ore' THEN v_ship.ore ELSE 0 END,
      organics = organics + CASE WHEN pc != 'organics' THEN v_ship.organics ELSE 0 END,
      goods = goods + CASE WHEN pc != 'goods' THEN v_ship.goods ELSE 0 END,
      energy = energy + CASE WHEN pc != 'energy' THEN v_ship.energy ELSE 0 END
    WHERE id = v_port.id;
    
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'trade_failed', 'message', 'Trade execution failed'));
  END;

  RETURN jsonb_build_object(
    'success', true,
    'trades', trade_summary,
    'total_proceeds', total_proceeds,
    'net_profit', total_proceeds - buy_cost,
    'new_credits', v_player.credits + total_proceeds - buy_cost
  );
END;
$$;

-- ============================================================================
-- 6. VERIFICATION QUERIES
-- ============================================================================

-- Verify the pricing updates
SELECT 
  kind,
  COUNT(*) as port_count,
  AVG(price_ore) as avg_ore_price,
  AVG(price_organics) as avg_organics_price,
  AVG(price_goods) as avg_goods_price,
  AVG(price_energy) as avg_energy_price
FROM ports 
WHERE kind != 'special'
GROUP BY kind
ORDER BY kind;

-- Test the enhanced pricing function
SELECT 
  'Test Enhanced Pricing' as test_name,
  calculate_price_multiplier(50000000, 'ore') as low_stock_multiplier,
  calculate_price_multiplier(100000000, 'ore') as normal_stock_multiplier,
  calculate_price_multiplier(200000000, 'ore') as high_stock_multiplier,
  calculate_price_multiplier(0, 'ore') as depleted_stock_multiplier;
