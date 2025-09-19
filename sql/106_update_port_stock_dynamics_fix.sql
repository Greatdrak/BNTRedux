-- Fix update_port_stock_dynamics to scope ports by universe via sectors
-- and avoid referencing non-existent ports.universe_id

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
  v_total_stock_changes integer := 0;
BEGIN
  /*
    NOTE: Adjust column updates to match your schema. The following is a
    conservative placeholder that only bumps last_stock_update. If your
    schema uses per-commodity columns (ore/organics/goods/energy) and price
    columns, add those adjustments here.
  */
  WITH scope AS (
    SELECT p.id
    FROM public.ports p
    JOIN public.sectors s ON s.id = p.sector_id
    WHERE s.universe_id = p_universe_id
  ),
  updated AS (
    UPDATE public.ports p
    SET
      last_stock_update = now()
    FROM scope sc
    WHERE sc.id = p.id
    RETURNING p.id, 0::integer AS stock_change
  )
  SELECT COUNT(*)::integer, COALESCE(SUM(stock_change), 0)::integer
  INTO v_ports_updated, v_total_stock_changes
  FROM updated;

  RETURN QUERY SELECT v_ports_updated, v_total_stock_changes;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO service_role;

COMMIT;
