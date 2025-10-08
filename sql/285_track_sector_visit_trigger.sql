-- Migration: 285_track_sector_visit_trigger.sql
-- Create trigger to stamp sectors.last_visited_* when players move sectors

-- Function to stamp last visited info
CREATE OR REPLACE FUNCTION public.track_sector_visit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only act when current_sector actually changes and is not null
  IF TG_OP = 'UPDATE' AND NEW.current_sector IS DISTINCT FROM OLD.current_sector AND NEW.current_sector IS NOT NULL THEN
    UPDATE public.sectors s
      SET last_visited_at = NOW(),
          last_visited_by = NEW.id
      WHERE s.universe_id = NEW.universe_id
        AND s.id = NEW.current_sector;  -- compare UUID to UUID
  END IF;
  RETURN NEW;
END;
$$;

-- Drop existing trigger if present to be idempotent
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'players' AND t.tgname = 'trg_track_sector_visit'
  ) THEN
    DROP TRIGGER trg_track_sector_visit ON public.players;
  END IF;
END $$;

-- Create the AFTER UPDATE trigger on players
CREATE TRIGGER trg_track_sector_visit
AFTER UPDATE OF current_sector ON public.players
FOR EACH ROW
EXECUTE FUNCTION public.track_sector_visit();
