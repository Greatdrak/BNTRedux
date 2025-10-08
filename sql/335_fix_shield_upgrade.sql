-- Migration: 335_fix_shield_upgrade.sql
-- Purpose: Remove shield_max references from game_ship_upgrade
-- Shields are calculated dynamically in combat, not stored as a max value

-- First, drop shield_max column if it exists (it's a generated column that's not needed)
ALTER TABLE public.ships DROP COLUMN IF EXISTS shield_max;

-- Drop the shield range constraint since it references shield_max
ALTER TABLE public.ships DROP CONSTRAINT IF EXISTS ships_shield_range;

-- Drop all existing overloads of game_ship_upgrade
DROP FUNCTION IF EXISTS public.game_ship_upgrade(uuid, text);
DROP FUNCTION IF EXISTS public.game_ship_upgrade(uuid, text, uuid);

-- Create the fixed game_ship_upgrade function
CREATE OR REPLACE FUNCTION public.game_ship_upgrade(p_user_id uuid, p_attr text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_cost INTEGER;
BEGIN
  -- Get player
  SELECT * INTO v_player FROM players WHERE user_id = p_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
  END IF;

  -- Get ship
  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Ship not found'));
  END IF;

  -- Validate attribute
  IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull') THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'invalid_attribute', 'message', 'Invalid upgrade attribute'));
  END IF;

  -- Calculate cost based on attribute
  CASE p_attr
    WHEN 'engine' THEN
      v_cost := 500 * (v_ship.engine_lvl + 1);
    WHEN 'computer' THEN
      v_cost := 400 * (v_ship.comp_lvl + 1);
    WHEN 'sensors' THEN
      v_cost := 400 * (v_ship.sensor_lvl + 1);
    WHEN 'shields' THEN
      v_cost := 300 * (v_ship.shield_lvl + 1);
    WHEN 'hull' THEN
      v_cost := 2000 * (v_ship.hull_lvl + 1);
  END CASE;

  -- Check if player has enough credits
  IF v_ship.credits < v_cost THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Insufficient credits for upgrade'));
  END IF;

  -- Apply upgrade
  CASE p_attr
    WHEN 'engine' THEN
      UPDATE ships SET engine_lvl = engine_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'computer' THEN
      UPDATE ships SET comp_lvl = comp_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'sensors' THEN
      UPDATE ships SET sensor_lvl = sensor_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'shields' THEN
      -- Just upgrade the level, shields are calculated dynamically in combat
      UPDATE ships SET shield_lvl = shield_lvl + 1 WHERE player_id = v_player.id;
    WHEN 'hull' THEN
      UPDATE ships SET 
        hull_lvl = hull_lvl + 1,
        hull = hull_max,
        cargo = FLOOR(100 * POWER(1.5, hull_lvl + 1))
      WHERE player_id = v_player.id;
  END CASE;

  -- Deduct credits from ship
  UPDATE ships SET credits = credits - v_cost WHERE id = v_ship.id;

  -- Get updated ship data
  SELECT * INTO v_ship FROM ships WHERE player_id = v_player.id;

  -- Return success with updated data
  RETURN jsonb_build_object(
    'ok', true,
    'credits', v_ship.credits,
    'ship', jsonb_build_object(
      'name', v_ship.name,
      'hull', v_ship.hull,
      'hull_max', v_ship.hull_max,
      'hull_lvl', v_ship.hull_lvl,
      'shield', v_ship.shield,
      'shield_lvl', v_ship.shield_lvl,
      'engine_lvl', v_ship.engine_lvl,
      'comp_lvl', v_ship.comp_lvl,
      'sensor_lvl', v_ship.sensor_lvl,
      'cargo', v_ship.cargo,
      'fighters', v_ship.fighters,
      'torpedoes', v_ship.torpedoes
    )
  );
END;
$$;

COMMENT ON FUNCTION public.game_ship_upgrade IS 'Upgrades ship attributes at regular ports. Shields are calculated dynamically in combat based on shield_lvl.';

