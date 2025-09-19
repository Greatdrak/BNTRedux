-- Fix rankings functions to use ship credits instead of player credits
-- The calculate_economic_score function is failing because it's trying to access credits from players table

-- Update calculate_economic_score function to use ship credits
DROP FUNCTION IF EXISTS public.calculate_economic_score(uuid, uuid);

CREATE OR REPLACE FUNCTION public.calculate_economic_score(
  p_player_id uuid,
  p_universe_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_score INTEGER := 0;
  v_credits INTEGER;
  v_trading_volume INTEGER;
  v_port_influence INTEGER;
BEGIN
  -- Get ship credits (moved from players table)
  SELECT COALESCE(s.credits, 0) INTO v_credits
  FROM players p
  JOIN ships s ON s.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Calculate trading volume (sum of all trade values)
  SELECT COALESCE(SUM(
    CASE 
      WHEN action = 'buy' THEN qty * price
      WHEN action = 'sell' THEN qty * price
      ELSE 0
    END
  ), 0) INTO v_trading_volume
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Calculate port influence (number of unique ports traded at)
  SELECT COUNT(DISTINCT port_id) INTO v_port_influence
  FROM trades t
  JOIN players p ON t.player_id = p.id
  WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
  
  -- Economic score formula: credits + (trading_volume / 1000) + (port_influence * 100)
  v_score := v_credits + (v_trading_volume / 1000) + (v_port_influence * 100);
  
  RETURN GREATEST(0, v_score);
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.calculate_economic_score(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_economic_score(uuid, uuid) TO service_role;
