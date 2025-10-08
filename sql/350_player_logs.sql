-- Player logs table
CREATE TABLE IF NOT EXISTS public.player_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  kind text NOT NULL, -- 'ship_scanned','ship_attacked','planet_scanned','planet_attacked'
  ref_id uuid NULL,   -- ship_id or planet_id or attacker player id
  message text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_player_logs_player_time ON public.player_logs(player_id, occurred_at DESC);


