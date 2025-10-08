-- Migration: 290_fix_game_hyperspace_overloads.sql
-- Purpose: Resolve function ambiguity for game_hyperspace and make 2-arg calls unambiguous
-- Strategy: Drop any ambiguous 2-arg version and create a wrapper that forwards to the 3-arg version

-- Drop the 2-arg overload if it exists to avoid ambiguity
DROP FUNCTION IF EXISTS public.game_hyperspace(uuid, integer);

-- Create an unambiguous 2-arg wrapper. The first UUID may be either player_id or user_id.
CREATE OR REPLACE FUNCTION public.game_hyperspace(
  p_id uuid,
  p_target_sector_number integer
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_id uuid;
  v_universe_id uuid;
BEGIN
  -- Treat p_id as player_id first
  SELECT user_id, universe_id
    INTO v_user_id, v_universe_id
  FROM public.players
  WHERE id = p_id
  LIMIT 1;

  -- If not a player_id, treat p_id as user_id
  IF v_user_id IS NULL THEN
    SELECT user_id, universe_id
      INTO v_user_id, v_universe_id
    FROM public.players
    WHERE user_id = p_id
    LIMIT 1;
  END IF;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'user_or_player_not_found');
  END IF;

  IF v_universe_id IS NULL THEN
    SELECT universe_id INTO v_universe_id
    FROM public.players
    WHERE user_id = v_user_id
    LIMIT 1;
  END IF;

  RETURN public.game_hyperspace(v_user_id, p_target_sector_number, v_universe_id);
END;
$$;
