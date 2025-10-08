-- Migration: 338_safe_fix_shield_upgrade.sql
-- Purpose: Remove shield_max references while preserving the better 3-parameter function

-- First, drop shield_max column if it exists
ALTER TABLE public.ships DROP COLUMN IF EXISTS shield_max CASCADE;

-- Drop both overloads
DROP FUNCTION IF EXISTS public.game_ship_upgrade(uuid, text);
DROP FUNCTION IF EXISTS public.game_ship_upgrade(uuid, text, uuid);

-- Recreate ONLY the 3-parameter version (the better one) with shield_max fixed
CREATE OR REPLACE FUNCTION public.game_ship_upgrade(
  p_user_id uuid, 
  p_attr text, 
  p_universe_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_player RECORD;
  v_ship RECORD;
  v_cost INTEGER;
  v_next_level INTEGER;
BEGIN
  -- Validate attribute (current set; future attrs can be added without changing costs)
  IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull', 'power', 'beam', 'torp_launcher', 'armor') THEN
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

  -- Calculate cost based on attribute (original BNT doubling formula: 1000 * 2^level)
  CASE p_attr
    WHEN 'engine' THEN
      v_cost := 1000 * POWER(2, v_ship.engine_lvl);
    WHEN 'computer' THEN
      v_cost := 1000 * POWER(2, v_ship.comp_lvl);
    WHEN 'sensors' THEN
      v_cost := 1000 * POWER(2, v_ship.sensor_lvl);
    WHEN 'shields' THEN
      v_cost := 1000 * POWER(2, v_ship.shield_lvl);
    WHEN 'hull' THEN
      v_cost := 1000 * POWER(2, v_ship.hull_lvl);
    WHEN 'power' THEN
      v_cost := 1000 * POWER(2, v_ship.power_lvl);
    WHEN 'beam' THEN
      v_cost := 1000 * POWER(2, v_ship.beam_lvl);
    WHEN 'torp_launcher' THEN
      v_cost := 1000 * POWER(2, v_ship.torp_launcher_lvl);
    WHEN 'armor' THEN
      v_cost := 1000 * POWER(2, v_ship.armor_lvl);
  END CASE;

  -- Check if ship has enough credits
  IF v_ship.credits < v_cost THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'insufficient_credits', 'message', 'Not enough credits'));
  END IF;

  -- Perform upgrade and deduct credits from ship
  CASE p_attr
    WHEN 'engine' THEN 
      UPDATE ships SET engine_lvl = engine_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'computer' THEN 
      UPDATE ships SET comp_lvl = comp_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'sensors' THEN 
      UPDATE ships SET sensor_lvl = sensor_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'shields' THEN 
      -- FIXED: Just upgrade level, shields are calculated dynamically in combat
      UPDATE ships SET shield_lvl = shield_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'hull' THEN 
      UPDATE ships SET 
        hull_lvl = hull_lvl + 1, 
        hull = hull_max, 
        credits = credits - v_cost,
        cargo = FLOOR(100 * POWER(1.5, hull_lvl + 1))
      WHERE player_id = v_player.id;
    WHEN 'power' THEN 
      UPDATE ships SET power_lvl = power_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'beam' THEN 
      UPDATE ships SET beam_lvl = beam_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'torp_launcher' THEN 
      UPDATE ships SET torp_launcher_lvl = torp_launcher_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
    WHEN 'armor' THEN 
      UPDATE ships SET armor_lvl = armor_lvl + 1, credits = credits - v_cost WHERE player_id = v_player.id;
  END CASE;

  -- Get updated ship data for response
  SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = v_player.id;

  RETURN jsonb_build_object(
    'ok', true, 
    'attribute', p_attr, 
    'next_level', CASE p_attr
      WHEN 'engine' THEN v_ship.engine_lvl
      WHEN 'computer' THEN v_ship.comp_lvl
      WHEN 'sensors' THEN v_ship.sensor_lvl
      WHEN 'shields' THEN v_ship.shield_lvl
      WHEN 'hull' THEN v_ship.hull_lvl
      WHEN 'power' THEN v_ship.power_lvl
      WHEN 'beam' THEN v_ship.beam_lvl
      WHEN 'torp_launcher' THEN v_ship.torp_launcher_lvl
      WHEN 'armor' THEN v_ship.armor_lvl
    END, 
    'cost', v_cost, 
    'credits_after', v_ship.credits
  );
END;
$function$;

COMMENT ON FUNCTION public.game_ship_upgrade IS 'Upgrades ship attributes at Special Ports. Uses BNT exponential cost formula (1000 * 2^level). Shields are calculated dynamically in combat.';

