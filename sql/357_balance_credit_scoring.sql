-- Migration: 357_balance_credit_scoring.sql
-- Purpose: Calculate actual credit investment in ship upgrades and add to score

-- Update the calculate_player_score function to reflect actual upgrade costs
CREATE OR REPLACE FUNCTION public.calculate_player_score(p_player_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ship_investment BIGINT := 0;
    v_credits BIGINT := 0;
    v_planet_value BIGINT := 0;
    v_exploration_score BIGINT := 0;
    v_total_score BIGINT := 0;
BEGIN
    -- Calculate total credits invested in ship upgrades
    -- Cost formula: 1000 * POWER(2, level) for each upgrade
    -- Sum of costs from level 0 to current level: SUM(1000 * 2^i) for i=0 to level-1
    -- This equals: 1000 * (2^level - 1)
    SELECT 
        COALESCE(
            -- Calculate total investment using geometric series formula
            (1000 * (POWER(2, engine_lvl) - 1)) +           -- Engine investment
            (1000 * (POWER(2, power_lvl) - 1)) +            -- Power investment
            (1000 * (POWER(2, comp_lvl) - 1)) +             -- Computer investment
            (1000 * (POWER(2, sensor_lvl) - 1)) +           -- Sensor investment
            (1000 * (POWER(2, beam_lvl) - 1)) +             -- Beam investment
            (1000 * (POWER(2, armor_lvl) - 1)) +            -- Armor investment (using armor_lvl not armor_max)
            (1000 * (POWER(2, cloak_lvl) - 1)) +            -- Cloak investment
            (1000 * (POWER(2, torp_launcher_lvl) - 1)) +    -- Torpedo investment
            (1000 * (POWER(2, shield_lvl) - 1)),            -- Shield investment
            0
        )
    INTO v_ship_investment
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
    SELECT COALESCE(turns_spent * 500, 0) INTO v_exploration_score
    FROM players 
    WHERE id = p_player_id;

    -- Calculate total score: ship investment + credits + planets + exploration
    -- Ship investment reflects actual credits spent on upgrades (exponential)
    -- Credits are current liquid credits (risk vs reward)
    -- Planet value is calculated commodities/assets
    -- Divide by 100 to keep scores in millions range
    v_total_score := (v_ship_investment + v_credits + v_planet_value + v_exploration_score) / 100;

    RETURN GREATEST(0, v_total_score);
END;
$$;