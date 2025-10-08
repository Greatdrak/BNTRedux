-- Migration: 282_update_universe_link_cap.sql
-- Ensure universe_settings has a per-sector link cap column and set a sane default

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='universe_settings' AND column_name='max_links_per_sector'
  ) THEN
    ALTER TABLE public.universe_settings ADD COLUMN max_links_per_sector INTEGER DEFAULT 15;
  END IF;
END $$;

-- Set default cap to 15 for all existing settings where null/zero
UPDATE public.universe_settings SET max_links_per_sector = 15 WHERE max_links_per_sector IS NULL OR max_links_per_sector < 2;

-- Explicitly set Alpha to 15
UPDATE public.universe_settings us
SET max_links_per_sector = 15
FROM public.universes u
WHERE us.universe_id = u.id AND u.name = 'Alpha';
