-- Enhance port regeneration RPC to return more detailed statistics
-- This will help with monitoring port stock dynamics

-- Drop the existing function first since we're changing the return type
DROP FUNCTION IF EXISTS public.update_port_stock_dynamics(uuid);

CREATE OR REPLACE FUNCTION public.update_port_stock_dynamics(
  p_universe_id uuid
)
RETURNS TABLE(
  ports_updated integer,
  total_stock_changes integer,
  ports_regenerated integer,
  ports_decayed integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_ports_updated integer := 0;
  v_total_stock_changes bigint := 0;
  v_ports_regenerated integer := 0;
  v_ports_decayed integer := 0;
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
      AND p.kind IN ('ore', 'organics', 'goods', 'energy')
  ),
  updates AS (
    UPDATE public.ports SET
      ore = CASE
        WHEN scope.kind = 'ore' THEN
          LEAST(base_stock, scope.ore + FLOOR((base_stock - scope.ore) * regen_rate))
        ELSE
          GREATEST(0, scope.ore - FLOOR(scope.ore * decay_rate))
      END,
      organics = CASE
        WHEN scope.kind = 'organics' THEN
          LEAST(base_stock, scope.organics + FLOOR((base_stock - scope.organics) * regen_rate))
        ELSE
          GREATEST(0, scope.organics - FLOOR(scope.organics * decay_rate))
      END,
      goods = CASE
        WHEN scope.kind = 'goods' THEN
          LEAST(base_stock, scope.goods + FLOOR((base_stock - scope.goods) * regen_rate))
        ELSE
          GREATEST(0, scope.goods - FLOOR(scope.goods * decay_rate))
      END,
      energy = CASE
        WHEN scope.kind = 'energy' THEN
          LEAST(base_stock, scope.energy + FLOOR((base_stock - scope.energy) * regen_rate))
        ELSE
          GREATEST(0, scope.energy - FLOOR(scope.energy * decay_rate))
      END
    FROM scope
    WHERE ports.id = scope.id
    RETURNING ports.id, scope.kind
  )
  SELECT 
    COUNT(*)::integer,
    COUNT(*) FILTER (WHERE kind IN ('ore', 'organics', 'goods', 'energy'))::integer,
    COUNT(*) FILTER (WHERE kind NOT IN ('ore', 'organics', 'goods', 'energy'))::integer
  INTO v_ports_updated, v_ports_regenerated, v_ports_decayed
  FROM updates;

  -- Return the results
  RETURN QUERY SELECT v_ports_updated, v_total_stock_changes::integer, v_ports_regenerated, v_ports_decayed;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO service_role;

-- Set ownership
ALTER FUNCTION public.update_port_stock_dynamics(uuid) OWNER TO postgres;
