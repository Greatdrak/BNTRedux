-- Create RPC function for port stock dynamics updates
-- This function updates port stock levels and pricing based on universe settings

CREATE OR REPLACE FUNCTION update_port_stock_dynamics(
  p_universe_id UUID
)
RETURNS TABLE(
  ports_updated INTEGER,
  total_stock_changes INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_ports_updated INTEGER := 0;
  v_total_stock_changes INTEGER := 0;
BEGIN
  -- Update port stock dynamics for all ports in the universe
  WITH updated_ports AS (
    UPDATE public.ports 
    SET 
      -- Random stock changes based on current stock levels
      stock = GREATEST(0, LEAST(stock_cap, stock + (RANDOM() * 20 - 10)::INTEGER)),
      -- Update pricing based on stock levels (higher stock = lower price)
      price_per_unit = GREATEST(1, price_per_unit + (RANDOM() * 4 - 2)::INTEGER),
      last_stock_update = NOW()
    WHERE 
      universe_id = p_universe_id
    RETURNING id, ABS(stock - LAG(stock) OVER (ORDER BY id)) as stock_change
  )
  SELECT 
    COUNT(*)::INTEGER,
    COALESCE(SUM(ABS(stock_change)), 0)::INTEGER
  INTO v_ports_updated, v_total_stock_changes
  FROM updated_ports;
  
  -- Return the results
  RETURN QUERY SELECT v_ports_updated, v_total_stock_changes;
END;
$$;

-- Grant execute permission to authenticated users and service role
GRANT EXECUTE ON FUNCTION update_port_stock_dynamics(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_port_stock_dynamics(UUID) TO service_role;
