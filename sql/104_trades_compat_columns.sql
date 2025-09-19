-- Ensure the trades table supports both legacy (qty, price) and newer (quantity, unit_price, total_price) columns
-- This avoids RPC failures where functions reference one or the other.

DO $$
BEGIN
  -- Add compatibility columns if they don't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'trades' AND column_name = 'quantity'
  ) THEN
    ALTER TABLE public.trades ADD COLUMN quantity bigint;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'trades' AND column_name = 'unit_price'
  ) THEN
    ALTER TABLE public.trades ADD COLUMN unit_price numeric;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'trades' AND column_name = 'total_price'
  ) THEN
    ALTER TABLE public.trades ADD COLUMN total_price numeric;
  END IF;

  -- Backfill from legacy columns if available
  PERFORM 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='trades' AND column_name='qty';
  IF FOUND THEN
    UPDATE public.trades SET quantity = COALESCE(quantity, qty);
  END IF;

  PERFORM 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='trades' AND column_name='price';
  IF FOUND THEN
    UPDATE public.trades 
    SET unit_price = COALESCE(unit_price, price),
        total_price = COALESCE(total_price, (COALESCE(quantity, qty)::numeric * price))
    WHERE unit_price IS NULL OR total_price IS NULL;
  END IF;
END $$;

-- Optional: create a simple trigger to keep columns in sync on new inserts (best-effort)
-- If functions insert into qty/price, copy to quantity/unit_price/total_price; if they insert into new columns, skip.
CREATE OR REPLACE FUNCTION public.trades_compat_sync()
RETURNS trigger AS $$
BEGIN
  IF NEW.quantity IS NULL AND NEW.qty IS NOT NULL THEN
    NEW.quantity := NEW.qty;
  END IF;
  IF NEW.unit_price IS NULL AND NEW.price IS NOT NULL THEN
    NEW.unit_price := NEW.price;
  END IF;
  IF NEW.total_price IS NULL AND NEW.price IS NOT NULL THEN
    NEW.total_price := COALESCE(NEW.quantity, NEW.qty)::numeric * NEW.price;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_trades_compat_sync ON public.trades;
CREATE TRIGGER trg_trades_compat_sync
BEFORE INSERT ON public.trades
FOR EACH ROW EXECUTE FUNCTION public.trades_compat_sync();
