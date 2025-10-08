-- Migration: Sector ownership logic based on planetary bases
-- A player owns a sector when they have 3+ planets with bases in that sector

-- Function to check and update sector ownership
CREATE OR REPLACE FUNCTION public.update_sector_ownership(p_sector_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sector RECORD;
  v_player_bases RECORD;
  v_new_owner UUID;
BEGIN
  -- Get current sector info
  SELECT id, number, universe_id, owner_player_id, name
  INTO v_sector
  FROM public.sectors
  WHERE id = p_sector_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Federation sectors (0-10) cannot change ownership
  IF v_sector.number BETWEEN 0 AND 10 THEN
    RETURN;
  END IF;

  -- Count bases per player in this sector
  SELECT 
    owner_player_id,
    COUNT(*) as base_count
  INTO v_player_bases
  FROM public.planets
  WHERE sector_id = p_sector_id
    AND owner_player_id IS NOT NULL
    AND base_built = true
  GROUP BY owner_player_id
  HAVING COUNT(*) >= 3
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- If a player has 3+ bases, they own the sector
  IF FOUND THEN
    v_new_owner := v_player_bases.owner_player_id;
  ELSE
    v_new_owner := NULL;
  END IF;

  -- Update ownership if changed
  IF v_new_owner IS DISTINCT FROM v_sector.owner_player_id THEN
    UPDATE public.sectors
    SET 
      owner_player_id = v_new_owner,
      controlled = (v_new_owner IS NOT NULL),
      name = CASE
        WHEN v_new_owner IS NULL THEN 'Uncharted Territory'
        WHEN v_new_owner IS NOT NULL AND (v_sector.name IS NULL OR v_sector.name = 'Uncharted Territory') THEN 'Uncharted Territory'
        ELSE v_sector.name
      END
    WHERE id = p_sector_id;

    IF v_new_owner IS NOT NULL THEN
      RAISE NOTICE 'Sector % is now owned by player %', v_sector.number, v_new_owner;
    ELSE
      RAISE NOTICE 'Sector % is now unowned', v_sector.number;
    END IF;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.update_sector_ownership(UUID) IS 'Updates sector ownership based on player having 3+ bases in the sector';

-- Trigger to update sector ownership when planet base status changes
CREATE OR REPLACE FUNCTION public.trigger_update_sector_ownership()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Check ownership for the affected sector
  IF TG_OP = 'DELETE' THEN
    PERFORM public.update_sector_ownership(OLD.sector_id);
  ELSE
    PERFORM public.update_sector_ownership(NEW.sector_id);
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS planet_ownership_trigger ON public.planets;
CREATE TRIGGER planet_ownership_trigger
  AFTER INSERT OR UPDATE OF owner_player_id, base_built OR DELETE ON public.planets
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_update_sector_ownership();

COMMENT ON TRIGGER planet_ownership_trigger ON public.planets IS 'Automatically updates sector ownership when planet bases change';

-- Function to rename a sector (only owner can rename)
CREATE OR REPLACE FUNCTION public.rename_sector(
  p_sector_id UUID,
  p_player_id UUID,
  p_new_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sector RECORD;
BEGIN
  -- Get sector info
  SELECT id, number, owner_player_id, name
  INTO v_sector
  FROM public.sectors
  WHERE id = p_sector_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'sector_not_found');
  END IF;

  -- Federation sectors cannot be renamed
  IF v_sector.number BETWEEN 0 AND 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'federation_sector', 'message', 'Federation sectors cannot be renamed');
  END IF;

  -- Only the owner can rename
  IF v_sector.owner_player_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'sector_not_owned', 'message', 'You must own this sector to rename it');
  END IF;

  IF v_sector.owner_player_id != p_player_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_owner', 'message', 'Only the sector owner can rename it');
  END IF;

  -- Validate name
  IF p_new_name IS NULL OR LENGTH(TRIM(p_new_name)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_name', 'message', 'Sector name cannot be empty');
  END IF;

  IF LENGTH(p_new_name) > 50 THEN
    RETURN jsonb_build_object('success', false, 'error', 'name_too_long', 'message', 'Sector name must be 50 characters or less');
  END IF;

  -- Update sector name
  UPDATE public.sectors
  SET name = TRIM(p_new_name)
  WHERE id = p_sector_id;

  RETURN jsonb_build_object('success', true, 'name', TRIM(p_new_name));
END;
$$;

COMMENT ON FUNCTION public.rename_sector(UUID, UUID, TEXT) IS 'Allows sector owner to rename their sector';

-- Function to update sector rules (only owner can update)
CREATE OR REPLACE FUNCTION public.update_sector_rules(
  p_sector_id UUID,
  p_player_id UUID,
  p_allow_attacking BOOLEAN DEFAULT NULL,
  p_allow_trading TEXT DEFAULT NULL,
  p_allow_planet_creation TEXT DEFAULT NULL,
  p_allow_sector_defense TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sector RECORD;
BEGIN
  -- Get sector info
  SELECT id, number, owner_player_id
  INTO v_sector
  FROM public.sectors
  WHERE id = p_sector_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'sector_not_found');
  END IF;

  -- Federation sectors cannot have rules changed
  IF v_sector.number BETWEEN 0 AND 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'federation_sector', 'message', 'Federation sector rules cannot be modified');
  END IF;

  -- Only the owner can update rules
  IF v_sector.owner_player_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'sector_not_owned', 'message', 'You must own this sector to set rules');
  END IF;

  IF v_sector.owner_player_id != p_player_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_owner', 'message', 'Only the sector owner can set rules');
  END IF;

  -- Update rules (only update fields that are provided)
  UPDATE public.sectors
  SET 
    allow_attacking = COALESCE(p_allow_attacking, allow_attacking),
    allow_trading = COALESCE(p_allow_trading, allow_trading),
    allow_planet_creation = COALESCE(p_allow_planet_creation, allow_planet_creation),
    allow_sector_defense = COALESCE(p_allow_sector_defense, allow_sector_defense)
  WHERE id = p_sector_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

COMMENT ON FUNCTION public.update_sector_rules(UUID, UUID, BOOLEAN, TEXT, TEXT, TEXT) IS 'Allows sector owner to update sector rules';

-- Set default names for existing sectors
UPDATE public.sectors
SET name = CASE
  WHEN number BETWEEN 0 AND 10 THEN 'Federation Territory'
  WHEN owner_player_id IS NULL THEN 'Uncharted Territory'
  ELSE COALESCE(name, 'Uncharted Territory')
END
WHERE name IS NULL OR name = '';

-- Recalculate all sector ownerships based on current base counts
DO $$
DECLARE
  v_sector RECORD;
BEGIN
  FOR v_sector IN SELECT id FROM public.sectors WHERE number > 10 LOOP
    PERFORM public.update_sector_ownership(v_sector.id);
  END LOOP;
END;
$$;

