-- Migration: 284_add_sector_last_visited.sql
-- Adds last_visited tracking to sectors and supporting index

ALTER TABLE public.sectors
  ADD COLUMN IF NOT EXISTS last_visited_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_visited_by UUID;

-- Optional FK to players (set null if player removed)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE table_name='sectors' AND constraint_name='sectors_last_visited_by_fkey'
  ) THEN
    ALTER TABLE public.sectors
      ADD CONSTRAINT sectors_last_visited_by_fkey
      FOREIGN KEY (last_visited_by)
      REFERENCES public.players(id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- Index to query recent visitors per universe or sector quickly
CREATE INDEX IF NOT EXISTS idx_sectors_last_visited_at ON public.sectors (last_visited_at DESC);
CREATE INDEX IF NOT EXISTS idx_sectors_last_visited_by ON public.sectors (last_visited_by);
