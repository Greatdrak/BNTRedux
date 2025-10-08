-- Migration: 279_fix_warp_limit_trigger.sql
-- Purpose: Ensure the warp cap is PER SECTOR, not per universe. Caps undirected degree
--          for both endpoints on INSERT into warps. Reads cap from universe_settings.max_links_per_sector
--          when available; defaults to 15.

-- Drop old trigger/function if they exist
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'check_warp_count') THEN
    DROP FUNCTION public.check_warp_count() CASCADE;
  END IF;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

-- Create new check function
CREATE OR REPLACE FUNCTION public.check_warp_degree() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_universe uuid := NEW.universe_id;
  v_from uuid;
  v_to uuid;
  v_cap int := 15;
  v_deg_from int;
  v_deg_to int;
BEGIN
  -- Allow for either column naming
  BEGIN v_from := NEW.from_sector; EXCEPTION WHEN undefined_column THEN v_from := NEW.from_sector_id; END;
  BEGIN v_to   := NEW.to_sector;   EXCEPTION WHEN undefined_column THEN v_to   := NEW.to_sector_id;   END;

  -- Load cap from universe_settings if present
  BEGIN
    SELECT COALESCE(max_links_per_sector, 15) INTO v_cap FROM universe_settings WHERE universe_id = v_universe LIMIT 1;
  EXCEPTION WHEN undefined_column THEN v_cap := 15; END;

  -- Compute undirected degree for both endpoints AFTER this insert
  SELECT COUNT(*) INTO v_deg_from FROM (
    SELECT DISTINCT CASE WHEN w.from_sector = v_from THEN w.to_sector ELSE w.from_sector END AS nbr
    FROM warps w
    WHERE w.universe_id = v_universe AND (w.from_sector = v_from OR w.to_sector = v_from)
    UNION ALL
    SELECT DISTINCT v_to
  ) q;

  SELECT COUNT(*) INTO v_deg_to FROM (
    SELECT DISTINCT CASE WHEN w.from_sector = v_to THEN w.to_sector ELSE w.from_sector END AS nbr
    FROM warps w
    WHERE w.universe_id = v_universe AND (w.from_sector = v_to OR w.to_sector = v_to)
    UNION ALL
    SELECT DISTINCT v_from
  ) q2;

  IF v_deg_from > v_cap OR v_deg_to > v_cap THEN
    RAISE EXCEPTION 'Warp cap exceeded (cap=%, from deg=%, to deg=%)', v_cap, v_deg_from, v_deg_to;
  END IF;

  RETURN NEW;
END;
$$;

-- Recreate trigger
DROP TRIGGER IF EXISTS warp_limit_trigger ON public.warps;
CREATE TRIGGER warp_limit_trigger
BEFORE INSERT ON public.warps
FOR EACH ROW
EXECUTE FUNCTION public.check_warp_degree();
