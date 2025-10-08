-- Migration: Sector rule enforcement helpers
-- Functions to validate player actions against sector rules

-- Helper function to check if a player can perform an action in a sector
CREATE OR REPLACE FUNCTION public.check_sector_permission(
  p_sector_id UUID,
  p_player_id UUID,
  p_action TEXT -- 'attack', 'trade', 'create_planet', 'deploy_defense'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sector RECORD;
  v_rule_value TEXT;
  v_is_owner BOOLEAN;
  v_is_ally BOOLEAN := false; -- TODO: Implement alliance system
BEGIN
  -- Get sector rules and ownership
  SELECT 
    owner_player_id,
    allow_attacking,
    allow_trading,
    allow_planet_creation,
    allow_sector_defense,
    number
  INTO v_sector
  FROM public.sectors
  WHERE id = p_sector_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'sector_not_found');
  END IF;

  -- Check if player owns the sector
  v_is_owner := (v_sector.owner_player_id = p_player_id);

  -- Get the relevant rule based on action
  CASE p_action
    WHEN 'attack' THEN
      IF NOT v_sector.allow_attacking THEN
        RETURN jsonb_build_object(
          'allowed', false, 
          'reason', 'combat_disabled',
          'message', 'Combat is not allowed in this sector.'
        );
      END IF;
      v_rule_value := 'yes'; -- Attacking is boolean, so if true we allow
      
    WHEN 'trade' THEN
      v_rule_value := v_sector.allow_trading;
      
    WHEN 'create_planet' THEN
      v_rule_value := v_sector.allow_planet_creation;
      
    WHEN 'deploy_defense' THEN
      v_rule_value := v_sector.allow_sector_defense;
      
    ELSE
      RETURN jsonb_build_object('allowed', false, 'reason', 'invalid_action');
  END CASE;

  -- For non-attack actions, check text rules
  IF p_action != 'attack' THEN
    IF v_rule_value = 'no' THEN
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'action_disabled',
        'message', 'This action is not allowed in this sector.'
      );
    ELSIF v_rule_value = 'allies_only' AND NOT v_is_owner AND NOT v_is_ally THEN
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'allies_only',
        'message', 'This action is restricted to the sector owner and their allies.'
      );
    END IF;
  END IF;

  -- Permission granted
  RETURN jsonb_build_object('allowed', true);
END;
$$;

COMMENT ON FUNCTION public.check_sector_permission(UUID, UUID, TEXT) IS 'Validates if a player can perform an action in a sector based on sector rules';

-- Update create_universe to apply Federation rules automatically
DROP FUNCTION IF EXISTS public.create_universe(TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.create_universe(
  p_name TEXT,
  p_sector_count INTEGER DEFAULT 100
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_universe_id UUID;
  v_sector_id UUID;
  i INTEGER;
BEGIN
  -- Create universe
  INSERT INTO public.universes (name, sector_count)
  VALUES (p_name, p_sector_count)
  RETURNING id INTO v_universe_id;

  -- Create sectors
  FOR i IN 0..(p_sector_count - 1) LOOP
    INSERT INTO public.sectors (universe_id, number)
    VALUES (v_universe_id, i);
  END LOOP;

  -- Apply Federation rules to sectors 0-10
  PERFORM public.apply_federation_rules(v_universe_id);

  RAISE NOTICE 'Created universe % with % sectors', p_name, p_sector_count;
  
  RETURN v_universe_id;
END;
$$;

COMMENT ON FUNCTION public.create_universe(TEXT, INTEGER) IS 'Creates a new universe with sectors and applies Federation safe zone rules';

