-- Simple fix for port regeneration - ensure proper integer handling
-- This should definitely work without integer overflow issues

BEGIN;

-- Drop the problematic function
DROP FUNCTION IF EXISTS public.update_port_stock_dynamics(uuid);

-- Create a simple, robust version
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
  port_record RECORD;
  new_ore integer;
  new_organics integer;
  new_goods integer;
  new_energy integer;
BEGIN
  -- Process each port individually to avoid integer overflow
  FOR port_record IN 
    SELECT p.id, p.kind, p.ore, p.organics, p.goods, p.energy
    FROM public.ports p
    JOIN public.sectors s ON s.id = p.sector_id
    WHERE s.universe_id = p_universe_id
      AND p.kind IN ('ore','organics','goods','energy')
  LOOP
    -- Initialize new values
    new_ore := port_record.ore;
    new_organics := port_record.organics;
    new_goods := port_record.goods;
    new_energy := port_record.energy;
    
    -- Handle each commodity based on port type
    CASE port_record.kind
      WHEN 'ore' THEN
        -- Ore port: regenerate ore toward 100M cap, decay others
        new_ore := LEAST(100000000, port_record.ore + ((100000000 - port_record.ore) * 0.1)::integer);
        new_organics := GREATEST(0, port_record.organics - (port_record.organics * 0.05)::integer);
        new_goods := GREATEST(0, port_record.goods - (port_record.goods * 0.05)::integer);
        new_energy := GREATEST(0, port_record.energy - (port_record.energy * 0.05)::integer);
        
      WHEN 'organics' THEN
        -- Organics port: regenerate organics toward 100M cap, decay others
        new_organics := LEAST(100000000, port_record.organics + ((100000000 - port_record.organics) * 0.1)::integer);
        new_ore := GREATEST(0, port_record.ore - (port_record.ore * 0.05)::integer);
        new_goods := GREATEST(0, port_record.goods - (port_record.goods * 0.05)::integer);
        new_energy := GREATEST(0, port_record.energy - (port_record.energy * 0.05)::integer);
        
      WHEN 'goods' THEN
        -- Goods port: regenerate goods toward 100M cap, decay others
        new_goods := LEAST(100000000, port_record.goods + ((100000000 - port_record.goods) * 0.1)::integer);
        new_ore := GREATEST(0, port_record.ore - (port_record.ore * 0.05)::integer);
        new_organics := GREATEST(0, port_record.organics - (port_record.organics * 0.05)::integer);
        new_energy := GREATEST(0, port_record.energy - (port_record.energy * 0.05)::integer);
        
      WHEN 'energy' THEN
        -- Energy port: regenerate energy toward 1B cap, decay others
        new_energy := LEAST(1000000000, port_record.energy + ((1000000000 - port_record.energy) * 0.1)::integer);
        new_ore := GREATEST(0, port_record.ore - (port_record.ore * 0.05)::integer);
        new_organics := GREATEST(0, port_record.organics - (port_record.organics * 0.05)::integer);
        new_goods := GREATEST(0, port_record.goods - (port_record.goods * 0.05)::integer);
    END CASE;
    
    -- Update the port
    UPDATE public.ports 
    SET 
      ore = new_ore,
      organics = new_organics,
      goods = new_goods,
      energy = new_energy
    WHERE id = port_record.id;
    
    -- Count changes
    v_ports_updated := v_ports_updated + 1;
    v_total_stock_changes := v_total_stock_changes + 
      ABS(new_ore - port_record.ore) +
      ABS(new_organics - port_record.organics) +
      ABS(new_goods - port_record.goods) +
      ABS(new_energy - port_record.energy);
  END LOOP;

  RETURN QUERY SELECT v_ports_updated, v_total_stock_changes;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_port_stock_dynamics(uuid) TO service_role;

COMMIT;
