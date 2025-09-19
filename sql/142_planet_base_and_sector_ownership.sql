-- Migration: Planet Base Building and Sector Ownership System
-- This migration adds support for planet base building, sector ownership, and related functionality

-- Add base building columns to planets table
ALTER TABLE public.planets
ADD COLUMN IF NOT EXISTS base_built BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS base_cost BIGINT DEFAULT 50000,
ADD COLUMN IF NOT EXISTS base_colonists_required BIGINT DEFAULT 10000,
ADD COLUMN IF NOT EXISTS base_resources_required BIGINT DEFAULT 10000;

-- Add sector ownership columns to sectors table
ALTER TABLE public.sectors
ADD COLUMN IF NOT EXISTS owner_player_id UUID REFERENCES public.players(id),
ADD COLUMN IF NOT EXISTS controlled BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS ownership_threshold INTEGER DEFAULT 3,
ADD COLUMN IF NOT EXISTS name TEXT;

-- Add universe settings columns for base building and sector ownership
ALTER TABLE public.universe_settings
ADD COLUMN IF NOT EXISTS planet_base_cost BIGINT DEFAULT 50000,
ADD COLUMN IF NOT EXISTS planet_base_colonists_required BIGINT DEFAULT 10000,
ADD COLUMN IF NOT EXISTS planet_base_resources_required BIGINT DEFAULT 10000,
ADD COLUMN IF NOT EXISTS sector_ownership_threshold INTEGER DEFAULT 3;

-- Create RPC function to rename a planet
CREATE OR REPLACE FUNCTION public.rename_planet(
    p_user_id UUID,
    p_planet_id UUID,
    p_new_name TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_planet RECORD;
    v_result JSON;
BEGIN
    -- Validate input
    IF p_new_name IS NULL OR TRIM(p_new_name) = '' THEN
        RETURN json_build_object('error', json_build_object('code', 'invalid_input', 'message', 'Planet name cannot be empty'));
    END IF;
    
    IF LENGTH(TRIM(p_new_name)) > 50 THEN
        RETURN json_build_object('error', json_build_object('code', 'invalid_input', 'message', 'Planet name cannot exceed 50 characters'));
    END IF;
    
    -- Get player info
    SELECT p.id INTO v_player_id
    FROM players p 
    WHERE p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Player not found'));
    END IF;
    
    -- Get planet info and verify ownership
    SELECT * INTO v_planet
    FROM planets pl
    WHERE pl.id = p_planet_id AND pl.owner_player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Planet not found or not owned by player'));
    END IF;
    
    -- Update planet name
    UPDATE planets
    SET name = TRIM(p_new_name)
    WHERE id = p_planet_id;
    
    v_result := json_build_object(
        'success', TRUE,
        'message', 'Planet renamed successfully',
        'planet_id', p_planet_id,
        'new_name', TRIM(p_new_name)
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', json_build_object('code', 'internal_error', 'message', 'Failed to rename planet'));
END;
$$;

-- Create RPC function to build a planet base
CREATE OR REPLACE FUNCTION public.build_planet_base(
    p_user_id UUID,
    p_planet_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_planet RECORD;
    v_ship RECORD;
    v_universe_settings RECORD;
    v_base_cost BIGINT;
    v_colonists_required BIGINT;
    v_resources_required BIGINT;
    v_result JSON;
BEGIN
    -- Get player info
    SELECT p.id INTO v_player_id
    FROM players p 
    WHERE p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Player not found'));
    END IF;
    
    -- Get planet info and verify ownership
    SELECT * INTO v_planet
    FROM planets pl
    WHERE pl.id = p_planet_id AND pl.owner_player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Planet not found or not owned by player'));
    END IF;
    
    -- Check if base already exists
    IF v_planet.base_built THEN
        RETURN json_build_object('error', json_build_object('code', 'already_exists', 'message', 'Planet base already built'));
    END IF;
    
    -- Get ship info for credit check
    SELECT * INTO v_ship
    FROM ships s
    WHERE s.player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Ship not found'));
    END IF;
    
    -- Get universe settings
    SELECT 
        us.planet_base_cost,
        us.planet_base_colonists_required,
        us.planet_base_resources_required
    INTO v_universe_settings
    FROM planets pl
    JOIN sectors s ON pl.sector_id = s.id
    JOIN universe_settings us ON s.universe_id = us.universe_id
    WHERE pl.id = p_planet_id;
    
    -- Set defaults if settings not found
    v_base_cost := COALESCE(v_universe_settings.planet_base_cost, 50000);
    v_colonists_required := COALESCE(v_universe_settings.planet_base_colonists_required, 10000);
    v_resources_required := COALESCE(v_universe_settings.planet_base_resources_required, 10000);
    
    -- Check requirements
    IF v_planet.colonists < v_colonists_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough colonists (need ' || v_colonists_required || ', have ' || v_planet.colonists || ')'));
    END IF;
    
    IF v_planet.ore < v_resources_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough ore (need ' || v_resources_required || ', have ' || v_planet.ore || ')'));
    END IF;
    
    IF v_planet.organics < v_resources_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough organics (need ' || v_resources_required || ', have ' || v_planet.organics || ')'));
    END IF;
    
    IF v_planet.goods < v_resources_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough goods (need ' || v_resources_required || ', have ' || v_planet.goods || ')'));
    END IF;
    
    IF v_planet.energy < v_resources_required THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_resources', 'message', 'Not enough energy (need ' || v_resources_required || ', have ' || v_planet.energy || ')'));
    END IF;
    
    IF v_ship.credits < v_base_cost THEN
        RETURN json_build_object('error', json_build_object('code', 'insufficient_funds', 'message', 'Not enough credits (need ' || v_base_cost || ', have ' || v_ship.credits || ')'));
    END IF;
    
    -- Build the base (consume resources and credits)
    UPDATE planets
    SET 
        base_built = TRUE,
        ore = ore - v_resources_required,
        organics = organics - v_resources_required,
        goods = goods - v_resources_required,
        energy = energy - v_resources_required
    WHERE id = p_planet_id;
    
    UPDATE ships
    SET credits = credits - v_base_cost
    WHERE player_id = v_player_id;
    
    -- Check for sector ownership
    PERFORM check_sector_ownership(v_planet.sector_id);
    
    v_result := json_build_object(
        'success', TRUE,
        'message', 'Planet base built successfully',
        'planet_id', p_planet_id,
        'base_cost', v_base_cost,
        'resources_consumed', v_resources_required
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', json_build_object('code', 'internal_error', 'message', 'Failed to build planet base'));
END;
$$;

-- Create RPC function to check sector ownership
CREATE OR REPLACE FUNCTION public.check_sector_ownership(
    p_sector_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sector RECORD;
    v_planets_with_bases INTEGER;
    v_ownership_threshold INTEGER;
    v_top_player RECORD;
    v_result JSON;
BEGIN
    -- Get sector info
    SELECT * INTO v_sector
    FROM sectors s
    WHERE s.id = p_sector_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'not_found', 'message', 'Sector not found'));
    END IF;
    
    -- Get ownership threshold from universe settings
    SELECT us.sector_ownership_threshold INTO v_ownership_threshold
    FROM universe_settings us
    WHERE us.universe_id = v_sector.universe_id;
    
    v_ownership_threshold := COALESCE(v_ownership_threshold, 3);
    
    -- Count planets with bases in this sector
    SELECT COUNT(*) INTO v_planets_with_bases
    FROM planets p
    WHERE p.sector_id = p_sector_id AND p.base_built = TRUE;
    
    -- If threshold met, find player with most bases
    IF v_planets_with_bases >= v_ownership_threshold THEN
        SELECT 
            p.owner_player_id,
            COUNT(*) as base_count
        INTO v_top_player
        FROM planets p
        WHERE p.sector_id = p_sector_id AND p.base_built = TRUE
        GROUP BY p.owner_player_id
        ORDER BY base_count DESC
        LIMIT 1;
        
        -- Update sector ownership
        UPDATE sectors
        SET 
            owner_player_id = v_top_player.owner_player_id,
            controlled = TRUE,
            name = (SELECT handle FROM players WHERE id = v_top_player.owner_player_id) || '''s Sector'
        WHERE id = p_sector_id;
        
        v_result := json_build_object(
            'success', TRUE,
            'message', 'Sector ownership updated',
            'sector_id', p_sector_id,
            'owner_player_id', v_top_player.owner_player_id,
            'sector_name', (SELECT handle FROM players WHERE id = v_top_player.owner_player_id) || '''s Sector'
        );
    ELSE
        v_result := json_build_object(
            'success', TRUE,
            'message', 'Sector ownership threshold not met',
            'sector_id', p_sector_id,
            'planets_with_bases', v_planets_with_bases,
            'threshold', v_ownership_threshold
        );
    END IF;
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', json_build_object('code', 'internal_error', 'message', 'Failed to check sector ownership'));
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.rename_planet(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.build_planet_base(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_sector_ownership(UUID) TO authenticated;
