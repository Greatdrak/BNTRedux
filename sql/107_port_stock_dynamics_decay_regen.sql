-- Port stock dynamics (decay non-native 5%, regenerate native toward 1B)
-- Scoped by universe via sectors.universe_id

BEGIN;

CREATE OR REPLACE FUNCTION public.update_port_stock_dynamics(
  p_universe_id uuid
)
RETURNS TABLE(
  ports_updated integer,
  total_stock_changes integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_ports_updated integer := 0;
  v_total_stock_changes bigint := 0;
  decay_rate numeric := 0.05;         -- 5% decay for non-native
  regen_rate numeric := 0.10;         -- 10% regeneration toward base for native
  base_stock bigint := 1000000000;    -- 1B
BEGIN
  /*
    Assumes ports table has integer columns: ore, organics, goods, energy, kind, sector_id.
    Native resource = kind; non-native resources decay.
  */
  WITH scope AS (
    SELECT p.id, p.kind, p.ore, p.organics, p.goods, p.energy
    FROM public.ports p
    JOIN public.sectors s ON s.id = p.sector_id
    WHERE s.universe_id = p_universe_id
      AND p.kind IN ('ore','organics','goods','energy')
  ),
  updated AS (
    UPDATE public.ports p SET
      ore = CASE
        WHEN p.kind = 'ore' THEN LEAST(base_stock, p.ore + FLOOR((base_stock - p.ore) * regen_rate)::bigint)
        ELSE GREATEST(0, p.ore - FLOOR(p.ore * decay_rate)::bigint)
      END,
      organics = CASE
        WHEN p.kind = 'organics' THEN LEAST(base_stock, p.organics + FLOOR((base_stock - p.organics) * regen_rate)::bigint)
        ELSE GREATEST(0, p.organics - FLOOR(p.organics * decay_rate)::bigint)
      END,
      goods = CASE
        WHEN p.kind = 'goods' THEN LEAST(base_stock, p.goods + FLOOR((base_stock - p.goods) * regen_rate)::bigint)
        ELSE GREATEST(0, p.goods - FLOOR(p.goods * decay_rate)::bigint)
      END,
      energy = CASE
        WHEN p.kind = 'energy' THEN LEAST(base_stock, p.energy + FLOOR((base_stock - p.energy) * regen_rate)::bigint)
        ELSE GREATEST(0, p.energy - FLOOR(p.energy * decay_rate)::bigint)
      END
    FROM scope sc
    WHERE sc.id = p.id
    RETURNING
      p.id,
      (ABS(p.ore - sc.ore)
       + ABS(p.organics - sc.organics)
       + ABS(p.goods - sc.goods)
       + ABS(p.energy - sc.energy))::bigint AS delta_sum
  )
  SELECT COUNT(*)::integer, COALESCE(SUM(delta_sum),0)
  INTO ports_updated, v_total_stock_changes
  FROM updated;

  RETURN QUERY SELECT ports_updated, v_total_stock_changes::integer;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO service_role;

COMMIT;
