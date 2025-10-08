-- Migration: 292_update_ai_runner_to_wrapper.sql
-- Purpose: Ensure AI uses the unambiguous ai_hyperspace wrapper

-- Update run_ai_player_actions to replace game_hyperspace calls with ai_hyperspace
DO $$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid)
  INTO v_def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'run_ai_player_actions'
  ORDER BY p.oid DESC
  LIMIT 1;

  IF v_def IS NOT NULL THEN
    -- Replace occurrences of game_hyperspace( with ai_hyperspace(
    v_def := replace(v_def, 'game_hyperspace(', 'ai_hyperspace(');

    -- Recreate function with updated body
    EXECUTE v_def;
  END IF;
END $$;
