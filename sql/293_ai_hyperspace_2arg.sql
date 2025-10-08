-- Migration: 293_ai_hyperspace_2arg.sql
-- Purpose: Provide a 2-arg ai_hyperspace wrapper for legacy AI calls

CREATE OR REPLACE FUNCTION public.ai_hyperspace(
  p_user_id uuid,
  p_target_sector_number integer
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_universe_id uuid;
BEGIN
  SELECT universe_id INTO v_universe_id
  FROM public.players
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_universe_id IS NULL THEN
    RETURN jsonb_build_object('error', 'universe_not_found_for_user');
  END IF;

  RETURN public.ai_hyperspace(p_user_id, p_target_sector_number, v_universe_id);
END;
$$;
