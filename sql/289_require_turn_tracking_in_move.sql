-- Migration: 289_require_turn_tracking_in_move.sql
-- Enforce turn tracking on every move

CREATE OR REPLACE FUNCTION public.game_move(
  p_user_id uuid,
  p_to_sector_number integer,
  p_universe_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_player_id uuid;
  v_current_sector_id uuid;
  v_target_sector_id uuid;
  v_turns integer;
  v_exists boolean;
BEGIN
  -- Get player in universe
  SELECT id, current_sector, turns
    INTO v_player_id, v_current_sector_id, v_turns
  FROM public.players
  WHERE user_id = p_user_id AND universe_id = p_universe_id
  LIMIT 1;

  IF v_player_id IS NULL THEN
    RETURN jsonb_build_object('error', 'player_not_found');
  END IF;

  -- Validate target sector exists in same universe
  SELECT id INTO v_target_sector_id
  FROM public.sectors
  WHERE universe_id = p_universe_id AND number = p_to_sector_number
  LIMIT 1;

  IF v_target_sector_id IS NULL THEN
    RETURN jsonb_build_object('error', 'target_sector_not_found');
  END IF;

  -- Check warp connectivity using sector UUIDs
  SELECT EXISTS (
    SELECT 1 FROM public.warps
    WHERE universe_id = p_universe_id
      AND from_sector = v_current_sector_id
      AND to_sector = v_target_sector_id
  ) INTO v_exists;

  IF NOT v_exists THEN
    RETURN jsonb_build_object('error', 'no_warp_connection');
  END IF;

  -- Ensure at least 1 turn
  IF COALESCE(v_turns, 0) < 1 THEN
    RETURN jsonb_build_object('error', 'insufficient_turns');
  END IF;

  -- Perform move: decrement turns and set sector
  UPDATE public.players
  SET current_sector = v_target_sector_id,
      turns = v_turns - 1
  WHERE id = v_player_id;

  -- Mandatory turn tracking
  PERFORM public.track_turn_spent(v_player_id);

  -- Return success with new sector number
  RETURN jsonb_build_object(
    'ok', true,
    'to', p_to_sector_number
  );
END;
$$;
