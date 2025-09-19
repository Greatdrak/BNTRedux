-- Fix port stock caps to match new base stock amounts (corrected version)
-- Ore, Organics, Goods: 100M cap (not 1B)
-- Energy: 1B cap (unchanged)

BEGIN;

-- Drop the old function to avoid conflicts
DROP FUNCTION IF EXISTS public.update_port_stock_dynamics(uuid);

-- Create the corrected function with proper caps and integer handling
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
  ore_cap integer := 100000000;        -- 100M cap for ore
  organics_cap integer := 100000000;   -- 100M cap for organics  
  goods_cap integer := 100000000;      -- 100M cap for goods
  energy_cap integer := 1000000000;    -- 1B cap for energy
BEGIN
  /*
    Port stock dynamics with correct caps:
    - Ore, Organics, Goods ports: 100M cap
    - Energy ports: 1B cap
    - Non-native commodities decay 5%
    - Native commodities regenerate 10% toward cap
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
        WHEN p.kind = 'ore' THEN LEAST(ore_cap, p.ore + FLOOR((ore_cap - p.ore) * regen_rate)::integer)
        ELSE GREATEST(0, p.ore - FLOOR(p.ore * decay_rate)::integer)
      END,
      organics = CASE
        WHEN p.kind = 'organics' THEN LEAST(organics_cap, p.organics + FLOOR((organics_cap - p.organics) * regen_rate)::integer)
        ELSE GREATEST(0, p.organics - FLOOR(p.organics * decay_rate)::integer)
      END,
      goods = CASE
        WHEN p.kind = 'goods' THEN LEAST(goods_cap, p.goods + FLOOR((goods_cap - p.goods) * regen_rate)::integer)
        ELSE GREATEST(0, p.goods - FLOOR(p.goods * decay_rate)::integer)
      END,
      energy = CASE
        WHEN p.kind = 'energy' THEN LEAST(energy_cap, p.energy + FLOOR((energy_cap - p.energy) * regen_rate)::integer)
        ELSE GREATEST(0, p.energy - FLOOR(p.energy * decay_rate)::integer)
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
  INTO v_ports_updated, v_total_stock_changes
  FROM updated;

  RETURN QUERY SELECT v_ports_updated, v_total_stock_changes::integer;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO service_role;

COMMIT;
