-- Add admin flag directly on players (per-universe). Use only if you prefer admin per player-row.

ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS is_admin boolean NOT NULL DEFAULT false;

-- Optional convenience: make a given user's players admin across all universes
-- UPDATE public.players SET is_admin = true WHERE user_id = '<your-user-id>';


