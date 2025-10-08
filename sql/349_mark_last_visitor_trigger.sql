-- Trigger to stamp sectors.last_player_visited whenever a player's current_sector changes
CREATE OR REPLACE FUNCTION public.trg_mark_last_visitor()
RETURNS trigger AS $$
BEGIN
  IF NEW.current_sector IS NOT NULL AND NEW.current_sector <> COALESCE(OLD.current_sector, '00000000-0000-0000-0000-000000000000') THEN
    UPDATE public.sectors
      SET last_player_visited = NEW.id,
          last_visited_at = now()
      WHERE id = NEW.current_sector;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'players_mark_last_visitor_trg'
  ) THEN
    CREATE TRIGGER players_mark_last_visitor_trg
    AFTER UPDATE OF current_sector ON public.players
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_mark_last_visitor();
  END IF;
END $$;


