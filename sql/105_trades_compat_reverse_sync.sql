-- Reverse sync for trades to satisfy legacy NOT NULL columns when new fields are used

DO $$
BEGIN
  -- Ensure legacy columns exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='trades' AND column_name='qty'
  ) THEN
    ALTER TABLE public.trades ADD COLUMN qty bigint;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='trades' AND column_name='price'
  ) THEN
    ALTER TABLE public.trades ADD COLUMN price numeric;
  END IF;
END $$;

-- Replace trigger with bidirectional syncing
CREATE OR REPLACE FUNCTION public.trades_compat_sync()
RETURNS trigger AS $$
BEGIN
  -- Legacy -> New
  IF NEW.quantity IS NULL AND NEW.qty IS NOT NULL THEN
    NEW.quantity := NEW.qty;
  END IF;
  IF NEW.unit_price IS NULL AND NEW.price IS NOT NULL THEN
    NEW.unit_price := NEW.price;
  END IF;
  IF NEW.total_price IS NULL AND NEW.price IS NOT NULL THEN
    NEW.total_price := COALESCE(NEW.quantity, NEW.qty)::numeric * NEW.price;
  END IF;

  -- New -> Legacy (to satisfy NOT NULL on qty/price in some schemas)
  IF NEW.qty IS NULL AND NEW.quantity IS NOT NULL THEN
    NEW.qty := NEW.quantity;
  END IF;
  IF NEW.price IS NULL AND NEW.unit_price IS NOT NULL THEN
    NEW.price := NEW.unit_price;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_trades_compat_sync ON public.trades;
CREATE TRIGGER trg_trades_compat_sync
BEFORE INSERT ON public.trades
FOR EACH ROW EXECUTE FUNCTION public.trades_compat_sync();
