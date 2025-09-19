-- Fix API routes that still reference inventories table
-- This migration updates the remaining API routes to use ships table instead

-- ============================================================================
-- 1. UPDATE /api/me ROUTE TO USE SHIPS TABLE
-- ============================================================================

-- The /api/me route needs to be updated to fetch inventory data from ships table
-- This is a code change, not a SQL migration, but we need to ensure the data structure is consistent

-- ============================================================================
-- 2. UPDATE /api/register ROUTE TO USE SHIPS TABLE  
-- ============================================================================

-- The /api/register route needs to be updated to not create inventories table entries
-- This is also a code change, not a SQL migration

-- ============================================================================
-- 3. VERIFY SHIPS TABLE HAS ALL INVENTORY COLUMNS
-- ============================================================================

-- Ensure ships table has all the inventory columns with proper defaults
ALTER TABLE public.ships 
ADD COLUMN IF NOT EXISTS colonists integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS ore integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS organics integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS goods integer DEFAULT 0,
ADD COLUMN IF NOT EXISTS energy integer DEFAULT 0;

-- Add constraints if they don't exist
DO $$
BEGIN
    -- Drop existing constraints if they exist
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_colonists_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_colonists_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_ore_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_ore_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_organics_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_organics_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_goods_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_goods_range;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ships_energy_range') THEN
        ALTER TABLE public.ships DROP CONSTRAINT ships_energy_range;
    END IF;
END $$;

-- Add constraints for inventory columns
ALTER TABLE public.ships 
ADD CONSTRAINT ships_colonists_range CHECK (colonists >= 0),
ADD CONSTRAINT ships_ore_range CHECK (ore >= 0),
ADD CONSTRAINT ships_organics_range CHECK (organics >= 0),
ADD CONSTRAINT ships_goods_range CHECK (goods >= 0),
ADD CONSTRAINT ships_energy_range CHECK (energy >= 0);

-- ============================================================================
-- 4. CREATE HELPER FUNCTION FOR INVENTORY DATA
-- ============================================================================

-- Create a helper function to get inventory data from ships table
CREATE OR REPLACE FUNCTION public.get_player_inventory(p_player_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_ship ships;
  v_inventory JSONB;
BEGIN
  SELECT * INTO v_ship FROM ships WHERE player_id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Ship not found');
  END IF;
  
  v_inventory := jsonb_build_object(
    'ore', v_ship.ore,
    'organics', v_ship.organics,
    'goods', v_ship.goods,
    'energy', v_ship.energy,
    'colonists', v_ship.colonists
  );
  
  RETURN v_inventory;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_player_inventory(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_player_inventory(uuid) TO service_role;

-- ============================================================================
-- 5. VERIFICATION QUERIES
-- ============================================================================

-- Verify ships table has inventory columns
SELECT column_name, data_type, column_default
FROM information_schema.columns 
WHERE table_name = 'ships' 
  AND table_schema = 'public'
  AND column_name IN ('ore', 'organics', 'goods', 'energy', 'colonists')
ORDER BY column_name;

-- Test the helper function
SELECT public.get_player_inventory(
  (SELECT id FROM players LIMIT 1)
) as sample_inventory;
