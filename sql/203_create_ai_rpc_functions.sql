-- Create proper RPC functions for AI management
-- Following proper database standards

-- Drop existing functions if they exist (to handle return type changes)
DROP FUNCTION IF EXISTS public.get_ai_players(UUID);
DROP FUNCTION IF EXISTS public.get_ai_statistics(UUID);

-- Function to get AI players for a universe
CREATE OR REPLACE FUNCTION public.get_ai_players(p_universe_id UUID)
RETURNS TABLE(
    player_id UUID,
    player_name TEXT,
    ship_id UUID,
    sector_number INTEGER,
    credits BIGINT,
    ai_personality TEXT,
    ship_levels JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id as player_id,
        p.handle as player_name,
        s.id as ship_id,
        sec.number as sector_number,
        s.credits,
        COALESCE(p.ai_personality::TEXT, 'balanced') as ai_personality,
        jsonb_build_object(
            'hull', COALESCE(s.hull_lvl, 1),
            'engine', COALESCE(s.engine_lvl, 1),
            'power', COALESCE(s.power_lvl, 1),
            'computer', COALESCE(s.comp_lvl, 1),
            'sensors', COALESCE(s.sensor_lvl, 1),
            'beam_weapon', COALESCE(s.beam_lvl, 1),
            'armor', COALESCE(s.armor_lvl, 1),
            'cloak', COALESCE(s.cloak_lvl, 1),
            'torp_launcher', COALESCE(s.torp_launcher_lvl, 1),
            'shield', COALESCE(s.shield_lvl, 1)
        ) as ship_levels
    FROM public.players p
    JOIN public.ships s ON p.id = s.player_id
    JOIN public.sectors sec ON p.current_sector = sec.id
    WHERE p.universe_id = p_universe_id 
    AND p.is_ai = TRUE
    ORDER BY p.handle;
END;
$$;

-- Function to get AI statistics for a universe
CREATE OR REPLACE FUNCTION public.get_ai_statistics(p_universe_id UUID)
RETURNS TABLE(
    total_ai_players INTEGER,
    trader_count INTEGER,
    explorer_count INTEGER,
    warrior_count INTEGER,
    colonizer_count INTEGER,
    balanced_count INTEGER,
    total_ai_credits BIGINT,
    total_ai_planets INTEGER,
    avg_ai_efficiency NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_players INTEGER := 0;
    v_trader_count INTEGER := 0;
    v_explorer_count INTEGER := 0;
    v_warrior_count INTEGER := 0;
    v_colonizer_count INTEGER := 0;
    v_balanced_count INTEGER := 0;
    v_total_credits BIGINT := 0;
    v_total_planets INTEGER := 0;
    v_avg_efficiency NUMERIC := 0;
BEGIN
    -- Count AI players by personality
    SELECT 
        COUNT(*)::INTEGER,
        COUNT(CASE WHEN ai_personality = 'trader' THEN 1 END)::INTEGER,
        COUNT(CASE WHEN ai_personality = 'explorer' THEN 1 END)::INTEGER,
        COUNT(CASE WHEN ai_personality = 'warrior' THEN 1 END)::INTEGER,
        COUNT(CASE WHEN ai_personality = 'colonizer' THEN 1 END)::INTEGER,
        COUNT(CASE WHEN ai_personality = 'balanced' OR ai_personality IS NULL THEN 1 END)::INTEGER,
        COALESCE(SUM(s.credits), 0)::BIGINT
    INTO 
        v_total_players,
        v_trader_count,
        v_explorer_count,
        v_warrior_count,
        v_colonizer_count,
        v_balanced_count,
        v_total_credits
    FROM public.players p
    JOIN public.ships s ON p.id = s.player_id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;

    -- Count AI owned planets
    SELECT COUNT(*)::INTEGER
    INTO v_total_planets
    FROM public.planets pl
    JOIN public.players p ON pl.owner_player_id = p.id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;

    -- Calculate average efficiency (credits per turn spent)
    SELECT COALESCE(AVG(CASE WHEN p.turns_spent > 0 THEN (s.credits::NUMERIC / p.turns_spent::NUMERIC) ELSE 0 END), 0)::NUMERIC
    INTO v_avg_efficiency
    FROM public.players p
    JOIN public.ships s ON p.id = s.player_id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;

    RETURN QUERY SELECT 
        v_total_players,
        v_trader_count,
        v_explorer_count,
        v_warrior_count,
        v_colonizer_count,
        v_balanced_count,
        v_total_credits,
        v_total_planets,
        v_avg_efficiency;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_ai_players(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ai_players(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_ai_statistics(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ai_statistics(UUID) TO service_role;
