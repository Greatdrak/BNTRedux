-- Fix AI Management Dashboard Data Issues
-- 
-- Issues identified:
-- 1. get_ai_statistics function doesn't exist
-- 2. ai_player_memory table doesn't exist
-- 3. AI players don't have ai_personality column
-- 4. Stats are not being calculated properly

-- 1. Add ai_personality column to players table if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'players' AND column_name = 'ai_personality') THEN
        ALTER TABLE players ADD COLUMN ai_personality TEXT DEFAULT 'balanced';
    END IF;
END $$;

-- 2. Check existing ai_player_memory table structure
-- The table already exists, so we'll just verify its structure
-- and populate it with existing AI players

-- 3. Create get_ai_statistics function
-- Drop existing function first to avoid return type conflicts
DROP FUNCTION IF EXISTS public.get_ai_statistics(UUID);

CREATE OR REPLACE FUNCTION public.get_ai_statistics(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_ai_players INTEGER;
    v_active_ai_players INTEGER;
    v_total_actions_today INTEGER;
    v_average_credits BIGINT;
    v_total_ai_planets INTEGER;
    v_personality_distribution JSON;
    v_result JSON;
BEGIN
    -- Count total AI players
    SELECT COUNT(*) INTO v_total_ai_players
    FROM players p
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;
    
    -- Count active AI players (those with recent activity)
    SELECT COUNT(*) INTO v_active_ai_players
    FROM players p
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = TRUE 
      AND p.last_turn_ts > NOW() - INTERVAL '24 hours';
    
    -- Count total actions today (sum of turns_spent for AI players)
    SELECT COALESCE(SUM(p.turns_spent), 0) INTO v_total_actions_today
    FROM players p
    WHERE p.universe_id = p_universe_id 
      AND p.is_ai = TRUE 
      AND p.last_turn_ts > NOW() - INTERVAL '24 hours';
    
    -- Calculate average credits for AI players
    SELECT COALESCE(AVG(s.credits), 0) INTO v_average_credits
    FROM players p
    JOIN ships s ON p.id = s.player_id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;
    
    -- Count AI owned planets
    SELECT COUNT(*) INTO v_total_ai_planets
    FROM planets pl
    JOIN players p ON pl.owner_player_id = p.id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE;
    
    -- Get personality distribution
    SELECT json_object_agg(
        ai_personality, 
        personality_count
    ) INTO v_personality_distribution
    FROM (
        SELECT 
            COALESCE(p.ai_personality, 'balanced') as ai_personality,
            COUNT(*) as personality_count
        FROM players p
        WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
        GROUP BY COALESCE(p.ai_personality, 'balanced')
    ) personality_stats;
    
    -- Build result
    v_result := json_build_object(
        'total_ai_players', v_total_ai_players,
        'active_ai_players', v_active_ai_players,
        'total_actions_today', v_total_actions_today,
        'average_credits', v_average_credits,
        'total_ai_planets', v_total_ai_planets,
        'personality_distribution', COALESCE(v_personality_distribution, '{}'::json)
    );
    
    RETURN v_result;
END;
$$;

-- 4. Grant permissions
GRANT ALL ON FUNCTION public.get_ai_statistics(UUID) TO anon;
GRANT ALL ON FUNCTION public.get_ai_statistics(UUID) TO authenticated;
GRANT ALL ON FUNCTION public.get_ai_statistics(UUID) TO service_role;

-- 5. Update existing AI players to have balanced personality
UPDATE players 
SET ai_personality = 'balanced' 
WHERE is_ai = TRUE AND ai_personality IS NULL;

-- 6. Create memory entries for existing AI players
-- Only insert if the table has the expected columns
DO $$
BEGIN
    -- Check if the table has the expected columns before inserting
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'ai_player_memory' 
        AND column_name = 'player_id'
    ) THEN
        INSERT INTO ai_player_memory (player_id)
        SELECT p.id
        FROM players p
        WHERE p.is_ai = TRUE
          AND NOT EXISTS (
            SELECT 1 FROM ai_player_memory m 
            WHERE m.player_id = p.id
          );
    END IF;
END $$;

-- 7. Test the function
SELECT 'Testing get_ai_statistics...' as status;
SELECT get_ai_statistics((SELECT id FROM universes LIMIT 1)) as test_result;
