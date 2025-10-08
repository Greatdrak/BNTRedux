-- Migration: 346_scale_up_player_scores.sql
-- Purpose: Scale up player scores to make them more meaningful and competitive

-- Update the calculate_player_score function to use better scaling
CREATE OR REPLACE FUNCTION public.calculate_player_score(p_player_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ship_value BIGINT := 0;
    v_credits BIGINT := 0;
    v_planet_value BIGINT := 0;
    v_exploration_score BIGINT := 0;
    v_total_score BIGINT := 0;
BEGIN
    -- Calculate ship value based on tech levels (increased multipliers)
    SELECT 
        COALESCE(
            (engine_lvl * 500000) +      -- Increased from 100,000
            (power_lvl * 750000) +       -- Increased from 150,000
            (comp_lvl * 1000000) +       -- Increased from 200,000
            (sensor_lvl * 875000) +      -- Increased from 175,000
            (beam_lvl * 1500000) +       -- Increased from 300,000
            (armor_max * 500) +          -- Increased from 100
            (cloak_lvl * 2000000) +     -- Increased from 400,000
            (torp_launcher_lvl * 1750000) + -- Increased from 350,000
            (shield_lvl * 1250000),     -- Increased from 250,000
            0
        )
    INTO v_ship_value
    FROM ships 
    WHERE player_id = p_player_id;

    -- Get ship credits (moved from players to ships table)
    SELECT COALESCE(credits, 0) INTO v_credits
    FROM ships 
    WHERE player_id = p_player_id;

    -- Calculate total planet value (commodities + colonists + credits)
    SELECT COALESCE(
        SUM(
            (ore * 5) +             -- Increased from 1 credit each
            (organics * 10) +       -- Increased from 2 credits each
            (goods * 25) +          -- Increased from 5 credits each
            (energy * 15) +         -- Increased from 3 credits each
            (colonists * 50) +      -- Increased from 10 credits each
            (fighters * 250) +      -- Increased from 50 credits each
            (torpedoes * 125) +     -- Increased from 25 credits each
            COALESCE(credits, 0)    -- Planet credits
        ), 0
    ) INTO v_planet_value
    FROM planets 
    WHERE owner_player_id = p_player_id;

    -- Calculate exploration score (sectors visited * 1000)
    -- This is a placeholder - we'll need to track sectors visited
    -- For now, we'll use a simple calculation based on turns spent
    SELECT COALESCE(turns_spent * 500, 0) INTO v_exploration_score -- Increased from 100
    FROM players 
    WHERE id = p_player_id;

    -- Calculate total score with much lighter scaling
    -- Apply 1:0.01 ratio (divide by 100) instead of 1:0.0001 (divide by 10,000)
    -- This will make scores 100x larger and more meaningful
    v_total_score := (v_ship_value + v_credits + v_planet_value + v_exploration_score) / 100;

    RETURN GREATEST(0, v_total_score);
END;
$$;
