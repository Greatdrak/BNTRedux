-- Restore the working game_planet_claim function
-- This fixes the broken function from the previous migration

DROP FUNCTION IF EXISTS public.game_planet_claim(uuid, uuid, text, uuid);

CREATE OR REPLACE FUNCTION public.game_planet_claim(
  p_user_id uuid,
  p_sector_number integer,
  p_name text DEFAULT 'Colony',
  p_universe_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID;
  v_sector_id UUID;
  v_universe_id UUID;
  v_planet_id UUID;
BEGIN
  -- Find player by auth user_id - filter by universe if provided
  IF p_universe_id IS NOT NULL THEN
    SELECT p.id, p.universe_id
    INTO v_player_id, v_universe_id
    FROM public.players p
    WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
  ELSE
    SELECT p.id, p.universe_id
    INTO v_player_id, v_universe_id
    FROM public.players p
    WHERE p.user_id = p_user_id;
  END IF;

  IF v_player_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Player not found'
    );
  END IF;

  -- Resolve target sector id in same universe
  SELECT id INTO v_sector_id 
  FROM public.sectors 
  WHERE number = p_sector_number AND universe_id = v_universe_id;

  IF v_sector_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Sector not found in your universe'
    );
  END IF;

  -- Check if planet exists in this sector
  SELECT id INTO v_planet_id 
  FROM public.planets 
  WHERE sector_id = v_sector_id AND owner_player_id IS NULL;

  IF v_planet_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'No unowned planet found in this sector'
    );
  END IF;

  -- Check if player has enough credits and turns
  IF NOT EXISTS (
    SELECT 1 FROM public.ships s 
    WHERE s.player_id = v_player_id 
    AND s.credits >= 10000
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Insufficient credits (need 10,000)'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.players p 
    WHERE p.id = v_player_id 
    AND p.turns >= 5
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Insufficient turns (need 5)'
    );
  END IF;

  -- Claim the planet
  UPDATE public.planets 
  SET 
    owner_player_id = v_player_id,
    name = p_name,
    colonists = 1000,
    ore = 0,
    organics = 0,
    goods = 0,
    energy = 0,
    fighters = 0,
    torpedoes = 0,
    credits = 0,
    production_ore_percent = 0,
    production_organics_percent = 0,
    production_goods_percent = 0,
    production_energy_percent = 0,
    production_fighters_percent = 0,
    production_torpedoes_percent = 0,
    base_built = false
  WHERE id = v_planet_id;

  -- Deduct credits and turns
  UPDATE public.ships 
  SET credits = credits - 10000 
  WHERE player_id = v_player_id;

  UPDATE public.players 
  SET turns = turns - 5 
  WHERE id = v_player_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Planet claimed successfully',
    'planet_id', v_planet_id,
    'planet_name', p_name,
    'credits_deducted', 10000,
    'turns_deducted', 5
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.game_planet_claim(uuid, integer, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_planet_claim(uuid, integer, text, uuid) TO service_role;
