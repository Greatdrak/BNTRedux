-- Fix planet transfer authentication bug

-- The issue is that the planet transfer API is checking player ownership
-- but there might be multiple players per user, causing mismatches

-- Step 1: Create a helper function to get the correct player for a user in a universe
CREATE OR REPLACE FUNCTION public.get_player_for_user_in_universe(p_user_id UUID, p_universe_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_player_id UUID;
BEGIN
  -- Get the player ID for this user in this universe
  -- If there are multiple players (due to the bug), get the first one
  SELECT id INTO v_player_id
  FROM players 
  WHERE user_id = p_user_id 
  AND universe_id = p_universe_id
  ORDER BY created_at ASC  -- Get the oldest player (first created)
  LIMIT 1;
  
  RETURN v_player_id;
END;
$$;

-- Step 2: Update the planet transfer API logic
-- This is a temporary fix until we clean up duplicate players

-- Create a function to check if a user owns a planet (handling multiple players)
CREATE OR REPLACE FUNCTION public.user_owns_planet(p_user_id UUID, p_universe_id UUID, p_planet_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  v_owns_planet BOOLEAN := FALSE;
BEGIN
  -- Check if any of the user's players in this universe own the planet
  SELECT EXISTS(
    SELECT 1 
    FROM planets p
    JOIN players pl ON p.owner_player_id = pl.id
    WHERE p.id = p_planet_id 
    AND pl.user_id = p_user_id 
    AND pl.universe_id = p_universe_id
  ) INTO v_owns_planet;
  
  RETURN v_owns_planet;
END;
$$;

-- Step 3: Create a function to get the correct player ID for planet operations
CREATE OR REPLACE FUNCTION public.get_planet_owner_player_id(p_user_id UUID, p_universe_id UUID, p_planet_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_player_id UUID;
BEGIN
  -- Get the player ID that owns the planet for this user
  SELECT pl.id INTO v_player_id
  FROM planets p
  JOIN players pl ON p.owner_player_id = pl.id
  WHERE p.id = p_planet_id 
  AND pl.user_id = p_user_id 
  AND pl.universe_id = p_universe_id
  LIMIT 1;
  
  RETURN v_player_id;
END;
$$;

-- Step 4: Test the functions
SELECT 
  'Function Test' as check_name,
  public.user_owns_planet(
    '397f60a3-4b79-4252-9e99-8aa3b7f87578'::UUID,  -- Nate Admin's user_id
    '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID,  -- Alpha universe
    'e41a8a13-cad9-4d9d-984c-82bbed494eac'::UUID   -- Jizzy planet
  ) as owns_jizzy_planet;

-- Step 5: Check what the correct player ID should be for planet operations
SELECT 
  'Correct Player ID' as check_name,
  public.get_planet_owner_player_id(
    '397f60a3-4b79-4252-9e99-8aa3b7f87578'::UUID,  -- Nate Admin's user_id
    '34ef41a9-a3a9-42b1-a174-3c55f70236da'::UUID,  -- Alpha universe
    'e41a8a13-cad9-4d9d-984c-82bbed494eac'::UUID   -- Jizzy planet
  ) as correct_player_id;
