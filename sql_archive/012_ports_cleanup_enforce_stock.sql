-- 012_ports_cleanup_enforce_stock.sql
-- Idempotent stock normalization for commodity ports

do $$
begin
  -- marker flag
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='ports' and column_name='stock_enforced') then
    alter table public.ports add column stock_enforced boolean not null default false;
  end if;
exception when duplicate_column then
  -- ignore
end$$;

-- Only enforce once
update public.ports p
set stock_enforced = true,
    ore       = case when kind='ore'       then coalesce(ore,0) else case when coalesce(ore,0) > 0 then ore else 0 end end,
    organics  = case when kind='organics'  then coalesce(organics,0) else case when coalesce(organics,0) > 0 then organics else 0 end end,
    goods     = case when kind='goods'     then coalesce(goods,0) else case when coalesce(goods,0) > 0 then goods else 0 end end,
    energy    = case when kind='energy'    then coalesce(energy,0) else case when coalesce(energy,0) > 0 then energy else 0 end end
where stock_enforced = false and kind in ('ore','organics','goods','energy');

-- Special ports keep 0 stock
update public.ports p
set ore=0, organics=0, goods=0, energy=0, stock_enforced=true
where stock_enforced=false and kind='special';


