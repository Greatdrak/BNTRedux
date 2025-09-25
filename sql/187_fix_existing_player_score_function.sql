-- Fix the existing calculate_player_score function to apply proper scaling
-- This is the function that get_leaderboard actually calls

CREATE OR REPLACE FUNCTION calculate_player_score(p_player_id UUID)
RETURNS BIGINT
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
    -- Calculate ship value based on tech levels
    SELECT 
        COALESCE(
            (engine_lvl * 100000) +
            (power_lvl * 150000) +
            (comp_lvl * 200000) +
            (sensor_lvl * 175000) +
            (beam_lvl * 300000) +
            (armor_max * 100) +          -- Use armor_max instead of armor_lvl
            (cloak_lvl * 400000) +
            (torp_launcher_lvl * 350000) +
            (shield_lvl * 250000),
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
            (ore * 1) +           -- Ore worth 1 credit each
            (organics * 2) +      -- Organics worth 2 credits each
            (goods * 5) +         -- Goods worth 5 credits each
            (energy * 3) +        -- Energy worth 3 credits each
            (colonists * 10) +    -- Colonists worth 10 credits each
            (fighters * 50) +     -- Fighters worth 50 credits each
            (torpedoes * 25) +    -- Torpedoes worth 25 credits each
            COALESCE(credits, 0)  -- Planet credits
        ), 0
    ) INTO v_planet_value
    FROM planets 
    WHERE owner_player_id = p_player_id;

    -- Calculate exploration score (sectors visited * 1000)
    -- This is a placeholder - we'll need to track sectors visited
    -- For now, we'll use a simple calculation based on turns spent
    SELECT COALESCE(turns_spent * 100, 0) INTO v_exploration_score
    FROM players 
    WHERE id = p_player_id;

    -- Calculate total score with lighter scaling
    -- Apply 1:0.0001 ratio (divide by 10,000) to bring billions down to hundred-thousands
    v_total_score := (v_ship_value + v_credits + v_planet_value + v_exploration_score) / 10000;

    RETURN GREATEST(0, v_total_score);
END;
$$;
