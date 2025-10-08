-- Migration: Add sector ownership rules
-- Adds columns to enforce sector-level restrictions on player actions

-- Add rule columns to sectors table
ALTER TABLE public.sectors 
ADD COLUMN IF NOT EXISTS allow_attacking BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS allow_trading TEXT DEFAULT 'yes' CHECK (allow_trading IN ('yes', 'no', 'allies_only')),
ADD COLUMN IF NOT EXISTS allow_planet_creation TEXT DEFAULT 'yes' CHECK (allow_planet_creation IN ('yes', 'no', 'allies_only')),
ADD COLUMN IF NOT EXISTS allow_sector_defense TEXT DEFAULT 'yes' CHECK (allow_sector_defense IN ('yes', 'no', 'allies_only'));

-- Add index for sector ownership lookups
CREATE INDEX IF NOT EXISTS idx_sectors_owner ON public.sectors(owner_player_id) WHERE owner_player_id IS NOT NULL;

-- Comment on columns
COMMENT ON COLUMN public.sectors.allow_attacking IS 'Whether combat is allowed in this sector';
COMMENT ON COLUMN public.sectors.allow_trading IS 'Trading restrictions: yes, no, or allies_only';
COMMENT ON COLUMN public.sectors.allow_planet_creation IS 'Planet creation restrictions: yes, no, or allies_only';
COMMENT ON COLUMN public.sectors.allow_sector_defense IS 'Mine deployment restrictions: yes, no, or allies_only';

-- Function to set Federation sector rules (sectors 0-10)
CREATE OR REPLACE FUNCTION public.apply_federation_rules(p_universe_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Set Federation sectors (0-10) as safe zones
  UPDATE public.sectors
  SET 
    allow_attacking = false,
    allow_planet_creation = 'no',
    allow_sector_defense = 'no',
    name = 'Federation Territory'
  WHERE universe_id = p_universe_id 
    AND number BETWEEN 0 AND 10;
    
  RAISE NOTICE 'Applied Federation rules to sectors 0-10 in universe %', p_universe_id;
END;
$$;

COMMENT ON FUNCTION public.apply_federation_rules(UUID) IS 'Applies Federation safe zone rules to sectors 0-10 in a universe';

-- Apply Federation rules to existing universes
DO $$
DECLARE
  v_universe RECORD;
BEGIN
  FOR v_universe IN SELECT id FROM public.universes LOOP
    PERFORM public.apply_federation_rules(v_universe.id);
  END LOOP;
END;
$$;

