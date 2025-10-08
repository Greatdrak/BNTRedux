-- Migration: 288_create_track_turn_spent.sql
-- Ensure turn tracking exists and is enforced for all actors

-- Add turns_spent to players if missing
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS turns_spent bigint NOT NULL DEFAULT 0;

-- Create or replace the tracking helper (compatible with existing calls)
CREATE OR REPLACE FUNCTION public.track_turn_spent(p_player_id uuid)
RETURNS void
LANGUAGE sql
AS $$
  UPDATE public.players
  SET turns_spent = COALESCE(turns_spent, 0) + 1
  WHERE id = p_player_id;
$$;
