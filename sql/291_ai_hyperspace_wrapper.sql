-- Migration: 291_ai_hyperspace_wrapper.sql
-- Purpose: Provide an unambiguous hyperspace helper for AI paths
-- The AI should call this function to avoid any overloading ambiguity.

CREATE OR REPLACE FUNCTION public.ai_hyperspace(
  p_user_id uuid,
  p_target_sector_number integer,
  p_universe_id uuid
)
RETURNS jsonb
LANGUAGE sql
AS $$
  SELECT public.game_hyperspace(p_user_id, p_target_sector_number, p_universe_id);
$$;

