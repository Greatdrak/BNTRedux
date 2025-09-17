-- 013_rpc_trade_auto.sql
-- Atomic auto-trade: sell all non-native, buy as much native commodity as possible

create or replace function public.game_trade_auto(p_user_id uuid, p_port uuid)
returns jsonb
language plpgsql
as $$
declare
  v_player record;
  v_ship record;
  v_port record;
  v_inv record;
  pc text; -- port commodity
  sell_price numeric; -- native sell price (0.90 * base)
  buy_prices jsonb;   -- other resources buy price (1.10 * base)
  proceeds numeric := 0;
  sold_ore int := 0; sold_organics int := 0; sold_goods int := 0; sold_energy int := 0;
  new_ore int; new_organics int; new_goods int; new_energy int;
  native_stock int; native_price numeric;
  credits_after numeric;
  capacity int; cargo_used int; cargo_after int; q int := 0;
  native_key text;
  err jsonb;
begin
  -- Load player, ship, port
  select * into v_player from public.players where user_id = p_user_id for update;
  if not found then return jsonb_build_object('error', jsonb_build_object('code','not_found','message','Player not found')); end if;

  select * into v_ship from public.ships where player_id = v_player.id for update;
  if not found then return jsonb_build_object('error', jsonb_build_object('code','not_found','message','Ship not found')); end if;

  select p.*, s.number as sector_number into v_port
  from public.ports p
  join public.sectors s on s.id = p.sector_id
  where p.id = p_port for update;
  if not found then return jsonb_build_object('error', jsonb_build_object('code','not_found','message','Port not found')); end if;
  if v_port.kind = 'special' then return jsonb_build_object('error', jsonb_build_object('code','invalid_port_kind','message','This is a Special port: no commodity trading.')); end if;

  -- Validate co-location
  if v_player.current_sector <> v_port.sector_id then
    return jsonb_build_object('error', jsonb_build_object('code','wrong_sector','message','Player not in port sector'));
  end if;

  pc := v_port.kind; -- ore|organics|goods|energy
  native_key := pc;

  -- pricing with dynamic stock-based multipliers
  native_price := case pc
    when 'ore' then v_port.price_ore * calculate_price_multiplier(v_port.ore)
    when 'organics' then v_port.price_organics * calculate_price_multiplier(v_port.organics)
    when 'goods' then v_port.price_goods * calculate_price_multiplier(v_port.goods)
    when 'energy' then v_port.price_energy * calculate_price_multiplier(v_port.energy)
  end;
  sell_price := native_price * 0.90; -- player buys from port at 0.90 * dynamic price

  -- compute proceeds from selling all non-native at 1.10 * dynamic price
  select * into v_inv from public.inventories where player_id = v_player.id for update;
  if not found then return jsonb_build_object('error', jsonb_build_object('code','not_found','message','Inventory not found')); end if;
  new_ore := v_inv.ore;
  new_organics := v_inv.organics;
  new_goods := v_inv.goods;
  new_energy := v_inv.energy;

  -- sell non-native resources with dynamic pricing
  if pc <> 'ore' and v_inv.ore > 0 then
    proceeds := proceeds + (v_port.price_ore * calculate_price_multiplier(v_port.ore) * 1.10) * v_inv.ore;
    sold_ore := v_inv.ore;
    new_ore := 0;
    v_port.ore := v_port.ore + sold_ore;
  end if;
  if pc <> 'organics' and v_inv.organics > 0 then
    proceeds := proceeds + (v_port.price_organics * calculate_price_multiplier(v_port.organics) * 1.10) * v_inv.organics;
    sold_organics := v_inv.organics;
    new_organics := 0;
    v_port.organics := v_port.organics + sold_organics;
  end if;
  if pc <> 'goods' and v_inv.goods > 0 then
    proceeds := proceeds + (v_port.price_goods * calculate_price_multiplier(v_port.goods) * 1.10) * v_inv.goods;
    sold_goods := v_inv.goods;
    new_goods := 0;
    v_port.goods := v_port.goods + sold_goods;
  end if;
  if pc <> 'energy' and v_inv.energy > 0 then
    proceeds := proceeds + (v_port.price_energy * calculate_price_multiplier(v_port.energy) * 1.10) * v_inv.energy;
    sold_energy := v_inv.energy;
    new_energy := 0;
    v_port.energy := v_port.energy + sold_energy;
  end if;

  -- credits and capacity after sells
  credits_after := v_player.credits + proceeds;
  cargo_used := new_ore + new_organics + new_goods + new_energy;
  capacity := v_ship.cargo - cargo_used;

  -- native stock and buy quantity
  native_stock := case pc
    when 'ore' then v_port.ore
    when 'organics' then v_port.organics
    when 'goods' then v_port.goods
    when 'energy' then v_port.energy
  end;

  q := least(native_stock, floor(credits_after / sell_price)::int, greatest(capacity,0));
  if q < 0 then q := 0; end if;

  -- apply buy
  if q > 0 then
    credits_after := credits_after - (q * sell_price);
    case pc
      when 'ore' then begin new_ore := new_ore + q; v_port.ore := v_port.ore - q; end;
      when 'organics' then begin new_organics := new_organics + q; v_port.organics := v_port.organics - q; end;
      when 'goods' then begin new_goods := new_goods + q; v_port.goods := v_port.goods - q; end;
      when 'energy' then begin new_energy := new_energy + q; v_port.energy := v_port.energy - q; end;
    end case;
  end if;

  -- persist changes
  update public.players
  set credits = credits_after
  where id = v_player.id;

  update public.inventories
  set ore = new_ore,
      organics = new_organics,
      goods = new_goods,
      energy = new_energy
  where player_id = v_player.id;

  update public.ports set
    ore = v_port.ore,
    organics = v_port.organics,
    goods = v_port.goods,
    energy = v_port.energy
  where id = p_port;

  return jsonb_build_object(
    'sold', jsonb_build_object('ore', sold_ore, 'organics', sold_organics, 'goods', sold_goods, 'energy', sold_energy),
    'bought', jsonb_build_object('resource', pc, 'qty', q),
    'credits', credits_after,
    'inventory_after', jsonb_build_object('ore', new_ore, 'organics', new_organics, 'goods', new_goods, 'energy', new_energy),
    'port_stock_after', jsonb_build_object('ore', v_port.ore, 'organics', v_port.organics, 'goods', v_port.goods, 'energy', v_port.energy),
    'prices', jsonb_build_object('pcSell', sell_price)
  );
end;
$$;


