-- Add last visitor tracking to sectors
ALTER TABLE public.sectors
  ADD COLUMN IF NOT EXISTS last_player_visited uuid NULL,
  ADD COLUMN IF NOT EXISTS last_visited_at timestamptz NULL;

-- Optional FK (safe if players table exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sectors_last_player_visited_fkey'
  ) THEN
    ALTER TABLE public.sectors
      ADD CONSTRAINT sectors_last_player_visited_fkey
      FOREIGN KEY (last_player_visited) REFERENCES public.players(id) ON DELETE SET NULL;
  END IF;
END $$;


