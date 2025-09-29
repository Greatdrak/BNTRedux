-- AI Statistics Function for Admin Dashboard

CREATE OR REPLACE FUNCTION public.get_ai_statistics(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
    v_total_ai_players INTEGER := 0;
    v_active_ai_players INTEGER := 0;
    v_total_actions_today INTEGER := 0;
    v_average_credits BIGINT := 0;
    v_total_ai_planets INTEGER := 0;
    v_personality_dist JSON;
BEGIN
    -- Count total AI players
    SELECT COUNT(*) INTO v_total_ai_players
    FROM players 
    WHERE universe_id = p_universe_id AND is_ai = TRUE;
    
    -- Count active AI players (those with memory records updated today)
    SELECT COUNT(DISTINCT m.player_id) INTO v_active_ai_players
    FROM ai_player_memory m
    JOIN players p ON m.player_id = p.id
    WHERE p.universe_id = p_universe_id 
    AND m.last_action >= CURRENT_DATE;
    
    -- Count total actions today (estimate based on memory updates)
    SELECT COUNT(*) INTO v_total_actions_today
    FROM ai_player_memory m
    JOIN players p ON m.player_id = p.id
    WHERE p.universe_id = p_universe_id 
    AND m.updated_at >= CURRENT_DATE;
    
    -- Calculate average credits of AI players
    SELECT COALESCE(AVG(s.credits), 0)::BIGINT INTO v_average_credits
    FROM players p
    JOIN ships s ON p.id = s.player_id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;
    
    -- Count total planets owned by AI players
    SELECT COUNT(*) INTO v_total_ai_planets
    FROM planets pl
    JOIN players p ON pl.owner_player_id = p.id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;
    
    -- Get personality distribution
    SELECT json_object_agg(
        COALESCE(ai_personality::TEXT, 'balanced'), 
        personality_count
    ) INTO v_personality_dist
    FROM (
        SELECT 
            ai_personality,
            COUNT(*) as personality_count
        FROM players 
        WHERE universe_id = p_universe_id AND is_ai = TRUE
        GROUP BY ai_personality
    ) personality_stats;
    
    -- Build result JSON
    v_result := json_build_object(
        'total_ai_players', v_total_ai_players,
        'active_ai_players', v_active_ai_players,
        'total_actions_today', v_total_actions_today,
        'average_credits', v_average_credits,
        'total_ai_planets', v_total_ai_planets,
        'personality_distribution', COALESCE(v_personality_dist, '{}'::json)
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', 'Failed to get AI statistics: ' || SQLERRM);
END;
$$;

-- Function to get detailed AI player performance metrics
CREATE OR REPLACE FUNCTION public.get_ai_performance_metrics(p_universe_id UUID)
RETURNS TABLE (
    player_id UUID,
    player_name TEXT,
    ai_personality TEXT,
    credits BIGINT,
    owned_planets INTEGER,
    total_actions INTEGER,
    last_action TIMESTAMP,
    current_goal TEXT,
    last_profit BIGINT,
    consecutive_losses INTEGER,
    performance_score FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id as player_id,
        p.name as player_name,
        p.ai_personality::TEXT,
        s.credits,
        COALESCE(m.owned_planets, 0) as owned_planets,
        COALESCE((
            SELECT COUNT(*) 
            FROM ai_player_memory mem 
            WHERE mem.player_id = p.id 
            AND mem.updated_at >= CURRENT_DATE - INTERVAL '7 days'
        ), 0)::INTEGER as total_actions,
        m.last_action,
        m.current_goal,
        COALESCE(m.last_profit, 0) as last_profit,
        COALESCE(m.consecutive_losses, 0) as consecutive_losses,
        -- Calculate performance score based on credits, planets, and recent activity
        (
            (s.credits / 10000.0) + 
            (COALESCE(m.owned_planets, 0) * 5.0) +
            (CASE WHEN m.last_action >= CURRENT_DATE - INTERVAL '1 day' THEN 10.0 ELSE 0.0 END) -
            (COALESCE(m.consecutive_losses, 0) * 2.0)
        ) as performance_score
    FROM players p
    JOIN ships s ON p.id = s.player_id
    LEFT JOIN ai_player_memory m ON p.id = m.player_id
    WHERE p.universe_id = p_universe_id 
    AND p.is_ai = TRUE
    ORDER BY performance_score DESC;
END;
$$;
