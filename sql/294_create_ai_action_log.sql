-- Migration: 294_create_ai_action_log.sql
-- Purpose: Persist per-action telemetry for AI behavior analysis

CREATE TABLE IF NOT EXISTS public.ai_action_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  universe_id uuid NOT NULL REFERENCES public.universes(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  action text NOT NULL,
  target_sector_id uuid,
  target_planet_id uuid,
  credits_before bigint,
  credits_after bigint,
  turns_before int,
  turns_after int,
  outcome text NOT NULL,
  message text
);

CREATE INDEX IF NOT EXISTS idx_ai_action_log_universe_created ON public.ai_action_log(universe_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_action_log_player_created ON public.ai_action_log(player_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_action_log_action ON public.ai_action_log(action);
