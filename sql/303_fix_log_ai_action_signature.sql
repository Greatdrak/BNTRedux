-- Migration: 303_fix_log_ai_action_signature.sql
-- Purpose: Create simplified log_ai_action function for AI runner

CREATE OR REPLACE FUNCTION public.log_ai_action(
  p_player_id uuid,
  p_universe_id uuid,
  p_action text,
  p_outcome text,
  p_message text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.ai_action_log (
    player_id,
    universe_id,
    action,
    outcome,
    message,
    created_at
  ) VALUES (
    p_player_id,
    p_universe_id,
    p_action,
    p_outcome,
    p_message,
    NOW()
  );
EXCEPTION WHEN OTHERS THEN
  -- Silently ignore logging errors to prevent AI from failing
  NULL;
END;
$$;
