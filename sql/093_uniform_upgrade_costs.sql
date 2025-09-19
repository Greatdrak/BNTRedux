-- Uniform upgrade costs across all ship attributes

-- 1) Table to store per-level upgrade cost (applies to all attributes)
CREATE TABLE IF NOT EXISTS public.upgrade_costs (
  level integer PRIMARY KEY,
  cost integer NOT NULL
);

-- 2) Seed default costs if table is empty (linear: 1000 * level). Adjust as desired.
INSERT INTO public.upgrade_costs(level, cost)
SELECT gs AS level, 1000 * gs AS cost
FROM generate_series(1, 50) AS gs
ON CONFLICT (level) DO NOTHING;

-- 3) Helper to get cost for a given next level with a sane fallback
CREATE OR REPLACE FUNCTION public.get_upgrade_cost(p_level integer)
RETURNS integer
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v_cost integer; BEGIN
  SELECT cost INTO v_cost FROM public.upgrade_costs WHERE level = p_level;
  IF v_cost IS NULL THEN
    -- Fallback policy if not seeded: 1000 * level
    v_cost := 1000 * GREATEST(p_level, 1);
  END IF;
  RETURN v_cost;
END $$;

-- 4) Replace cost logic in game_ship_upgrade to use uniform cost table
CREATE OR REPLACE FUNCTION public.game_ship_upgrade(
  p_user_id uuid,
  p_attr text,
  p_universe_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_cost INTEGER;
  v_next_level INTEGER;
BEGIN
  -- Validate attribute (current set; future attrs can be added without changing costs)
  IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
  END IF;

  -- Get player (optionally universe scoped)
  IF p_universe_id IS NOT NULL THEN
    SELECT p.* INTO v_player FROM players p WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id FOR UPDATE;
  ELSE
    SELECT p.* INTO v_player FROM players p WHERE p.user_id = p_user_id FOR UPDATE;
  END IF;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship
  SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = v_player.id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  -- Must be at Special port
  IF NOT EXISTS (
    SELECT 1 FROM ports p JOIN sectors s ON p.sector_id = s.id
    WHERE s.id = v_player.current_sector AND p.kind = 'special'
  ) THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'wrong_port', 'message', 'Must be at a Special port to upgrade'));
  END IF;

  -- Determine next level and uniform cost
  v_next_level := CASE p_attr
    WHEN 'engine' THEN v_ship.engine_lvl + 1
    WHEN 'computer' THEN v_ship.comp_lvl + 1
    WHEN 'sensors' THEN v_ship.sensor_lvl + 1
    WHEN 'shields' THEN v_ship.shield_lvl + 1
    WHEN 'hull' THEN v_ship.hull_lvl + 1
  END;
  v_cost := public.get_upgrade_cost(v_next_level);

  IF v_player.credits < v_cost THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
  END IF;

  -- Perform upgrade
  CASE p_attr
    WHEN 'engine' THEN UPDATE ships SET engine_lvl = engine_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'computer' THEN UPDATE ships SET comp_lvl = comp_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'sensors' THEN UPDATE ships SET sensor_lvl = sensor_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'shields' THEN UPDATE ships SET shield_lvl = shield_lvl + 1, shield = shield_max WHERE player_id = v_player.id;
    WHEN 'hull' THEN UPDATE ships SET hull_lvl = hull_lvl + 1, hull = hull_max WHERE player_id = v_player.id;
  END CASE;

  -- Deduct credits
  UPDATE players SET credits = credits - v_cost WHERE id = v_player.id;

  RETURN jsonb_build_object('ok', true, 'attribute', p_attr, 'next_level', v_next_level, 'cost', v_cost, 'credits_after', v_player.credits - v_cost);
END;
$$;


