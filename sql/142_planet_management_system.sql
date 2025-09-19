-- Planet Management System: Renaming, Base Building, and Sector Ownership
-- This migration adds planet management features and sector ownership mechanics

-- Add planet management columns
ALTER TABLE public.planets 
ADD COLUMN IF NOT EXISTS base_built boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS base_cost bigint DEFAULT 50000 CHECK (base_cost >= 0),
ADD COLUMN IF NOT EXISTS rename_cost bigint DEFAULT 1000 CHECK (rename_cost >= 0);

-- Add sector ownership tracking
ALTER TABLE public.sectors 
ADD COLUMN IF NOT EXISTS owner_player_id uuid REFERENCES public.players(id),
ADD COLUMN IF NOT EXISTS ownership_threshold integer DEFAULT 3 CHECK (ownership_threshold >= 1),
ADD COLUMN IF NOT EXISTS controlled boolean DEFAULT false;

-- Add universe settings for sector ownership
ALTER TABLE public.universe_settings 
ADD COLUMN IF NOT EXISTS sector_ownership_threshold integer DEFAULT 3 CHECK (sector_ownership_threshold >= 1),
ADD COLUMN IF NOT EXISTS planet_base_cost bigint DEFAULT 50000 CHECK (planet_base_cost >= 0),
ADD COLUMN IF NOT EXISTS planet_rename_cost bigint DEFAULT 1000 CHECK (planet_rename_cost >= 0);

-- Create function to check sector ownership
CREATE OR REPLACE FUNCTION public.check_sector_ownership(
  p_sector_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sector RECORD;
  v_threshold integer;
  v_planet_count integer;
  v_owner_player_id uuid;
  v_result json;
BEGIN
  -- Get sector and threshold
  SELECT s.*, us.sector_ownership_threshold INTO v_sector, v_threshold
  FROM sectors s
  JOIN universes u ON u.id = s.universe_id
  JOIN universe_settings us ON us.universe_id = u.id
  WHERE s.id = p_sector_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Sector not found');
  END IF;
  
  -- Count owned planets in sector
  SELECT COUNT(*) INTO v_planet_count
  FROM planets p
  WHERE p.sector_id = p_sector_id 
    AND p.owner_player_id IS NOT NULL;
  
  -- Check if sector should be controlled
  IF v_planet_count >= v_threshold THEN
    -- Find the player who owns the most planets in this sector
    SELECT p.owner_player_id INTO v_owner_player_id
    FROM planets p
    WHERE p.sector_id = p_sector_id 
      AND p.owner_player_id IS NOT NULL
    GROUP BY p.owner_player_id
    ORDER BY COUNT(*) DESC
    LIMIT 1;
    
    -- Update sector ownership
    UPDATE sectors 
    SET 
      owner_player_id = v_owner_player_id,
      controlled = true,
      ownership_threshold = v_threshold
    WHERE id = p_sector_id;
    
    v_result := json_build_object(
      'controlled', true,
      'owner_player_id', v_owner_player_id,
      'planet_count', v_planet_count,
      'threshold', v_threshold
    );
  ELSE
    -- Sector is not controlled
    UPDATE sectors 
    SET 
      owner_player_id = NULL,
      controlled = false,
      ownership_threshold = v_threshold
    WHERE id = p_sector_id;
    
    v_result := json_build_object(
      'controlled', false,
      'owner_player_id', NULL,
      'planet_count', v_planet_count,
      'threshold', v_threshold
    );
  END IF;
  
  RETURN v_result;
END;
$$;

-- Create function to rename planet
CREATE OR REPLACE FUNCTION public.rename_planet(
  p_user_id uuid,
  p_planet_id uuid,
  p_new_name text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid;
  v_ship_credits bigint;
  v_rename_cost bigint;
  v_result json;
BEGIN
  -- Validate input
  IF p_new_name IS NULL OR LENGTH(TRIM(p_new_name)) = 0 THEN
    RETURN json_build_object('error', 'Planet name cannot be empty');
  END IF;
  
  IF LENGTH(p_new_name) > 50 THEN
    RETURN json_build_object('error', 'Planet name too long (max 50 characters)');
  END IF;
  
  -- Get player and ship data
  SELECT p.id, s.credits, us.planet_rename_cost
  INTO v_player_id, v_ship_credits, v_rename_cost
  FROM players p
  JOIN ships s ON s.player_id = p.id
  JOIN universes u ON u.id = p.universe_id
  JOIN universe_settings us ON us.universe_id = u.id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Player not found');
  END IF;
  
  -- Check if player owns the planet
  IF NOT EXISTS (
    SELECT 1 FROM planets 
    WHERE id = p_planet_id 
      AND owner_player_id = v_player_id
  ) THEN
    RETURN json_build_object('error', 'You do not own this planet');
  END IF;
  
  -- Check if player has enough credits
  IF v_ship_credits < v_rename_cost THEN
    RETURN json_build_object('error', 'Insufficient credits');
  END IF;
  
  -- Update planet name and deduct credits
  UPDATE planets 
  SET name = TRIM(p_new_name)
  WHERE id = p_planet_id;
  
  UPDATE ships 
  SET credits = credits - v_rename_cost
  WHERE player_id = v_player_id;
  
  RETURN json_build_object(
    'success', true,
    'new_name', TRIM(p_new_name),
    'cost', v_rename_cost,
    'remaining_credits', v_ship_credits - v_rename_cost
  );
END;
$$;

-- Create function to build planet base
CREATE OR REPLACE FUNCTION public.build_planet_base(
  p_user_id uuid,
  p_planet_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid;
  v_ship_credits bigint;
  v_base_cost bigint;
  v_planet_name text;
  v_result json;
BEGIN
  -- Get player and ship data
  SELECT p.id, s.credits, us.planet_base_cost, pl.name
  INTO v_player_id, v_ship_credits, v_base_cost, v_planet_name
  FROM players p
  JOIN ships s ON s.player_id = p.id
  JOIN universes u ON u.id = p.universe_id
  JOIN universe_settings us ON us.universe_id = u.id
  JOIN planets pl ON pl.id = p_planet_id
  WHERE p.user_id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Player not found');
  END IF;
  
  -- Check if player owns the planet
  IF NOT EXISTS (
    SELECT 1 FROM planets 
    WHERE id = p_planet_id 
      AND owner_player_id = v_player_id
  ) THEN
    RETURN json_build_object('error', 'You do not own this planet');
  END IF;
  
  -- Check if base is already built
  IF EXISTS (
    SELECT 1 FROM planets 
    WHERE id = p_planet_id 
      AND base_built = true
  ) THEN
    RETURN json_build_object('error', 'Base is already built on this planet');
  END IF;
  
  -- Check if player has enough credits
  IF v_ship_credits < v_base_cost THEN
    RETURN json_build_object('error', 'Insufficient credits');
  END IF;
  
  -- Build base and deduct credits
  UPDATE planets 
  SET base_built = true
  WHERE id = p_planet_id;
  
  UPDATE ships 
  SET credits = credits - v_base_cost
  WHERE player_id = v_player_id;
  
  -- Check sector ownership after base is built
  PERFORM check_sector_ownership((SELECT sector_id FROM planets WHERE id = p_planet_id));
  
  RETURN json_build_object(
    'success', true,
    'planet_name', v_planet_name,
    'cost', v_base_cost,
    'remaining_credits', v_ship_credits - v_base_cost,
    'tech_bonus', 1
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.check_sector_ownership(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_sector_ownership(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.rename_planet(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rename_planet(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.build_planet_base(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.build_planet_base(uuid, uuid) TO service_role;
