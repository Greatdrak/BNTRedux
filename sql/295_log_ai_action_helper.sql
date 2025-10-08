-- Migration: 295_log_ai_action_helper.sql
-- Purpose: Helper to write standardized AI action logs

CREATE OR REPLACE FUNCTION public.log_ai_action(
  p_universe_id uuid,
  p_player_id uuid,
  p_action text,
  p_target_sector_id uuid,
  p_target_planet_id uuid,
  p_credits_before bigint,
  p_credits_after bigint,
  p_turns_before int,
  p_turns_after int,
  p_outcome text,
  p_message text
)
RETURNS void
LANGUAGE sql
AS $$
  INSERT INTO public.ai_action_log (
    universe_id, player_id, action, target_sector_id, target_planet_id,
    credits_before, credits_after, turns_before, turns_after, outcome, message
  ) VALUES (
    p_universe_id, p_player_id, p_action, p_target_sector_id, p_target_planet_id,
    p_credits_before, p_credits_after, p_turns_before, p_turns_after, p_outcome, p_message
  );
$$;
