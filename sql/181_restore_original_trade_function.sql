-- Restore the original working game_trade_auto function from backup
-- This was working before we broke it

-- Drop existing functions first
DROP FUNCTION IF EXISTS public.calculate_price_multiplier(integer);
DROP FUNCTION IF EXISTS public.calculate_price_multiplier(integer, integer);
DROP FUNCTION IF EXISTS public.calculate_price_multiplier(integer, text, integer);
DROP FUNCTION IF EXISTS public.game_trade(UUID, UUID, TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.game_trade(UUID, UUID, TEXT, TEXT, INTEGER, UUID);
DROP FUNCTION IF EXISTS public.game_trade_auto(UUID, UUID);
DROP FUNCTION IF EXISTS public.game_trade_auto(UUID, UUID, UUID);

-- Restore the original calculate_price_multiplier function from backup
CREATE OR REPLACE FUNCTION "public"."calculate_price_multiplier"("current_stock" integer, "port_kind" "text" DEFAULT 'ore'::"text", "base_stock" integer DEFAULT NULL::integer) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
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
  
  -- Use logarithmic scaling for smooth price transitions
  log_factor := LOG(10, GREATEST(stock_ratio, 0.01)); -- Clamp to avoid log(0)
  
  -- Scale log factor to price range (0.5 to 2.0)
  multiplier := 2.0 - (log_factor + 2) * 0.5; -- log(0.01) ≈ -2, log(100) ≈ 2
  multiplier := GREATEST(0.5, LEAST(2.0, multiplier)); -- Clamp to range
  
  RETURN multiplier;
END;
$$;

-- Restore the original working function from backup
CREATE OR REPLACE FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Simply call the 3-parameter version with NULL universe_id
    RETURN public.game_trade_auto(p_user_id, p_port, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."game_trade_auto"("p_user_id" "uuid", "p_port" "uuid", "p_universe_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_port RECORD;
    pc TEXT; -- port commodity
    sell_price NUMERIC; -- native sell price (0.90 * base)
    proceeds NUMERIC := 0;
    sold_ore INT := 0; sold_organics INT := 0; sold_goods INT := 0; sold_energy INT := 0;
    new_ore INT; new_organics INT; new_goods INT; new_energy INT;
    native_stock INT; native_price NUMERIC;
    credits_after NUMERIC;
    ship_cargo_capacity INT;
    current_cargo INT;
    remaining_cargo INT;
    cargo_after INT; q INT := 0;
    native_key TEXT;
BEGIN
    -- Load player, ship, port - filter by universe if provided
    IF p_universe_id IS NOT NULL THEN
        SELECT * INTO v_player FROM public.players WHERE user_id = p_user_id AND universe_id = p_universe_id FOR UPDATE;
    ELSE
        SELECT * INTO v_player FROM public.players WHERE user_id = p_user_id FOR UPDATE;
    END IF;
    
    IF NOT FOUND THEN 
        RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Player not found')); 
    END IF;

    SELECT * INTO v_ship FROM public.ships WHERE player_id = v_player.id FOR UPDATE;
    IF NOT FOUND THEN 
        RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Ship not found')); 
    END IF;

    SELECT p.*, s.number as sector_number INTO v_port
    FROM public.ports p
    JOIN public.sectors s ON s.id = p.sector_id
    WHERE p.id = p_port FOR UPDATE;
    IF NOT FOUND THEN 
        RETURN jsonb_build_object('error', jsonb_build_object('code','not_found','message','Port not found')); 
    END IF;
    
    IF v_port.kind = 'special' THEN 
        RETURN jsonb_build_object('error', jsonb_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.')); 
    END IF;

    -- Validate co-location
    IF v_player.current_sector <> v_port.sector_id THEN
        RETURN jsonb_build_object('error', jsonb_build_object('code','wrong_sector','message','Player not in port sector'));
    END IF;

    pc := v_port.kind; -- ore|organics|goods|energy
    native_key := pc;

    -- Calculate ship cargo capacity using BNT formula
    ship_cargo_capacity := FLOOR(100 * POWER(1.5, COALESCE(v_ship.hull_lvl, 1)));
    
    -- Get current cargo load
    current_cargo := v_ship.ore + v_ship.organics + v_ship.goods + v_ship.energy;
    remaining_cargo := GREATEST(0, ship_cargo_capacity - current_cargo);

    -- Initialize new quantities with current values
    new_ore := v_ship.ore;
    new_organics := v_ship.organics;
    new_goods := v_ship.goods;
    new_energy := v_ship.energy;

    -- pricing with dynamic stock-based multipliers
    native_price := case pc
        when 'ore' then v_port.price_ore * calculate_price_multiplier(v_port.ore)
        when 'organics' then v_port.price_organics * calculate_price_multiplier(v_port.organics)
        when 'goods' then v_port.price_goods * calculate_price_multiplier(v_port.goods)
        when 'energy' then v_port.price_energy * calculate_price_multiplier(v_port.energy)
    end;
    sell_price := native_price * 0.90; -- sell price (player buys)

    -- Sell all non-native resources first
    if v_ship.ore > 0 and pc <> 'ore' then
        q := v_ship.ore;
        sold_ore := q;
        proceeds := proceeds + (q * v_port.price_ore * calculate_price_multiplier(v_port.ore) * 1.10);
        new_ore := 0;
        v_port.ore := v_port.ore + sold_ore;
    end if;

    if v_ship.organics > 0 and pc <> 'organics' then
        q := v_ship.organics;
        sold_organics := q;
        proceeds := proceeds + (q * v_port.price_organics * calculate_price_multiplier(v_port.organics) * 1.10);
        new_organics := 0;
        v_port.organics := v_port.organics + sold_organics;
    end if;

    if v_ship.goods > 0 and pc <> 'goods' then
        q := v_ship.goods;
        sold_goods := q;
        proceeds := proceeds + (q * v_port.price_goods * calculate_price_multiplier(v_port.goods) * 1.10);
        new_goods := 0;
        v_port.goods := v_port.goods + sold_goods;
    end if;

    if v_ship.energy > 0 and pc <> 'energy' then
        q := v_ship.energy;
        sold_energy := q;
        proceeds := proceeds + (q * v_port.price_energy * calculate_price_multiplier(v_port.energy) * 1.10);
        new_energy := 0;
        v_port.energy := v_port.energy + sold_energy;
    end if;

    -- Update ship credits with proceeds from selling
    UPDATE public.ships SET credits = credits + proceeds WHERE id = v_ship.id;

    -- Get updated ship credits after selling
    SELECT credits INTO credits_after FROM public.ships WHERE id = v_ship.id;

    -- Calculate remaining cargo space after selling
    cargo_after := new_ore + new_organics + new_goods + new_energy;
    remaining_cargo := GREATEST(0, ship_cargo_capacity - cargo_after);

    -- Get native stock
    native_stock := case pc
        when 'ore' then v_port.ore
        when 'organics' then v_port.organics
        when 'goods' then v_port.goods
        when 'energy' then v_port.energy
    end;

    -- Buy native commodity - ALWAYS try to buy if there's space and credits, even with no cargo
    IF remaining_cargo > 0 AND native_stock > 0 AND credits_after > 0 THEN
        -- Calculate how much we can afford and fit
        q := LEAST(
            FLOOR(credits_after / sell_price),  -- What we can afford
            native_stock,                       -- What port has
            remaining_cargo                     -- What fits in cargo
        );
        
        IF q > 0 THEN
            -- Update ship inventory with native commodity
            CASE pc
                WHEN 'ore' THEN
                    new_ore := new_ore + q;
                    v_port.ore := v_port.ore - q;
                WHEN 'organics' THEN
                    new_organics := new_organics + q;
                    v_port.organics := v_port.organics - q;
                WHEN 'goods' THEN
                    new_goods := new_goods + q;
                    v_port.goods := v_port.goods - q;
                WHEN 'energy' THEN
                    new_energy := new_energy + q;
                    v_port.energy := v_port.energy - q;
            END CASE;
            
            -- Deduct cost from ship credits
            UPDATE public.ships SET 
                credits = credits - (q * sell_price),
                ore = new_ore,
                organics = new_organics,
                goods = new_goods,
                energy = new_energy
            WHERE id = v_ship.id;
        END IF;
    END IF;

    -- Update port stock
    UPDATE public.ports SET 
        ore = v_port.ore,
        organics = v_port.organics,
        goods = v_port.goods,
        energy = v_port.energy
    WHERE id = p_port;

    -- Get final ship data
    SELECT credits, ore, organics, goods, energy INTO credits_after, new_ore, new_organics, new_goods, new_energy
    FROM public.ships WHERE id = v_ship.id;

    -- Return success
    RETURN jsonb_build_object(
        'ok', true,
        'port', jsonb_build_object(
            'kind', v_port.kind,
            'sector_number', v_port.sector_number
        ),
        'trades', jsonb_build_object(
            'sold', jsonb_build_object(
                'ore', sold_ore,
                'organics', sold_organics,
                'goods', sold_goods,
                'energy', sold_energy
            ),
            'bought', jsonb_build_object(
                pc, q
            )
        ),
        'credits', jsonb_build_object(
            'before', credits_after - proceeds + (q * sell_price),
            'after', credits_after
        ),
        'cargo', jsonb_build_object(
            'capacity', ship_cargo_capacity,
            'used', new_ore + new_organics + new_goods + new_energy,
            'free', ship_cargo_capacity - (new_ore + new_organics + new_goods + new_energy)
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Exception in restored game_trade_auto: %', SQLERRM;
        RETURN jsonb_build_object('error', jsonb_build_object('code','internal_error','message','Internal server error: ' || SQLERRM));
END;
$$;
