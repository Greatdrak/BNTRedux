-- Enhanced AI System for Xenobe Players
-- This EXTENDS the existing AI system with personality types and strategic behaviors
-- It does NOT replace the existing AI players or leaderboard integration

-- Create AI personality types enum (only if it doesn't exist)
DO $$ BEGIN
    CREATE TYPE ai_personality AS ENUM ('trader', 'explorer', 'warrior', 'colonizer', 'balanced');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Add personality column to players table (only if it doesn't exist)
ALTER TABLE players ADD COLUMN IF NOT EXISTS ai_personality ai_personality DEFAULT 'balanced';

-- Create AI memory/state table for persistent decision making (only if it doesn't exist)
CREATE TABLE IF NOT EXISTS ai_player_memory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    last_action TIMESTAMP DEFAULT NOW(),
    current_goal TEXT,
    target_sector_id UUID,
    trade_route JSONB,
    exploration_targets JSONB DEFAULT '[]'::jsonb,
    owned_planets INTEGER DEFAULT 0,
    last_profit BIGINT DEFAULT 0,
    consecutive_losses INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create index for performance (only if it doesn't exist)
CREATE INDEX IF NOT EXISTS idx_ai_player_memory_player_id ON ai_player_memory(player_id);

-- Create enhanced AI decision making function
CREATE OR REPLACE FUNCTION public.run_enhanced_ai_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    ai_player RECORD;
    ai_memory RECORD;
    actions_taken INTEGER := 0;
    v_result JSON;
    v_decision TEXT;
    v_action_result BOOLEAN;
BEGIN
    -- Process each AI player
    FOR ai_player IN 
        SELECT p.id, p.handle as name, p.ai_personality, 
               s.id as ship_id, s.credits, p.current_sector as sector_id, s.ore, s.organics, s.goods, s.energy, s.colonists,
               s.hull_lvl, s.engine_lvl, s.power_lvl, s.comp_lvl, s.sensor_lvl, s.beam_lvl,
               s.armor_lvl, s.cloak_lvl, s.torp_launcher_lvl, s.shield_lvl, s.fighters, s.torpedoes,
               sec.number as sector_number, sec.universe_id
        FROM public.players p
        JOIN public.ships s ON p.id = s.player_id
        JOIN public.sectors sec ON p.current_sector = sec.id
        WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
    LOOP
        -- Get or create AI memory
        SELECT * INTO ai_memory FROM ai_player_memory WHERE player_id = ai_player.id;
        
        IF NOT FOUND THEN
            INSERT INTO ai_player_memory (player_id, current_goal)
            VALUES (ai_player.id, 'explore')
            RETURNING * INTO ai_memory;
        END IF;
        
        -- Make decisions based on personality
        v_decision := public.ai_make_decision(ai_player, ai_memory);
        
        -- Execute the decision
        v_action_result := public.ai_execute_action(ai_player, ai_memory, v_decision);
        
        IF v_action_result THEN
            actions_taken := actions_taken + 1;
        END IF;
        
        -- Update AI memory
        UPDATE ai_player_memory 
        SET last_action = NOW(), 
            updated_at = NOW()
        WHERE player_id = ai_player.id;
    END LOOP;
    
    v_result := json_build_object(
        'success', TRUE,
        'message', 'Enhanced AI actions completed',
        'actions_taken', actions_taken,
        'universe_id', p_universe_id
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', 'Failed to run enhanced AI actions: ' || SQLERRM);
END;
$$;

-- AI Decision Making Function
CREATE OR REPLACE FUNCTION public.ai_make_decision(ai_player RECORD, ai_memory RECORD)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_decision TEXT := 'explore';
    v_credits_threshold BIGINT;
    v_random_factor FLOAT := RANDOM();
BEGIN
    -- Set thresholds based on personality
    CASE ai_player.ai_personality
        WHEN 'trader' THEN v_credits_threshold := 5000;
        WHEN 'explorer' THEN v_credits_threshold := 15000;
        WHEN 'warrior' THEN v_credits_threshold := 8000;
        WHEN 'colonizer' THEN v_credits_threshold := 12000;
        ELSE v_credits_threshold := 10000; -- balanced
    END CASE;
    
    -- Decision tree based on personality and current state
    IF ai_player.ai_personality = 'trader' THEN
        -- Traders prioritize profitable trading
        IF ai_player.credits < 2000 THEN
            v_decision := 'emergency_trade';
        ELSIF v_random_factor < 0.7 THEN
            v_decision := 'optimize_trade';
        ELSIF ai_player.credits > 20000 AND v_random_factor < 0.9 THEN
            v_decision := 'upgrade_ship';
        ELSE
            v_decision := 'explore_markets';
        END IF;
        
    ELSIF ai_player.ai_personality = 'explorer' THEN
        -- Explorers prioritize movement and discovery
        IF ai_player.credits < 5000 THEN
            v_decision := 'trade_for_funds';
        ELSIF v_random_factor < 0.6 THEN
            v_decision := 'strategic_explore';
        ELSIF v_random_factor < 0.8 THEN
            v_decision := 'claim_planet';
        ELSE
            v_decision := 'upgrade_engines';
        END IF;
        
    ELSIF ai_player.ai_personality = 'warrior' THEN
        -- Warriors prioritize combat readiness and aggression
        IF ai_player.credits < 3000 THEN
            v_decision := 'raid_trade';
        ELSIF ai_player.fighters < 50 AND ai_player.credits > 10000 THEN
            v_decision := 'buy_fighters';
        ELSIF v_random_factor < 0.5 THEN
            v_decision := 'upgrade_weapons';
        ELSIF v_random_factor < 0.8 THEN
            v_decision := 'patrol_territory';
        ELSE
            v_decision := 'strategic_move';
        END IF;
        
    ELSIF ai_player.ai_personality = 'colonizer' THEN
        -- Colonizers prioritize planet acquisition and management
        IF ai_player.credits < 8000 THEN
            v_decision := 'resource_gather';
        ELSIF v_random_factor < 0.6 THEN
            v_decision := 'claim_planet';
        ELSIF v_random_factor < 0.8 THEN
            v_decision := 'manage_planets';
        ELSE
            v_decision := 'expand_territory';
        END IF;
        
    ELSE -- balanced personality
        -- Balanced approach to all activities
        IF ai_player.credits < 5000 THEN
            v_decision := 'basic_trade';
        ELSIF v_random_factor < 0.3 THEN
            v_decision := 'trade_goods';
        ELSIF v_random_factor < 0.5 THEN
            v_decision := 'claim_planet';
        ELSIF v_random_factor < 0.7 THEN
            v_decision := 'upgrade_ship';
        ELSIF v_random_factor < 0.9 THEN
            v_decision := 'strategic_move';
        ELSE
            v_decision := 'explore';
        END IF;
    END IF;
    
    RETURN v_decision;
END;
$$;

-- AI Action Execution Function
CREATE OR REPLACE FUNCTION public.ai_execute_action(ai_player RECORD, ai_memory RECORD, action TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_success BOOLEAN := FALSE;
    v_port RECORD;
    v_planet RECORD;
    v_target_sector RECORD;
    v_profit BIGINT;
    v_cost BIGINT;
BEGIN
    CASE action
        WHEN 'optimize_trade' THEN
            v_success := public.ai_optimize_trading(ai_player);
            
        WHEN 'emergency_trade' THEN
            v_success := public.ai_emergency_trade(ai_player);
            
        WHEN 'strategic_explore' THEN
            v_success := public.ai_strategic_explore(ai_player, ai_memory);
            
        WHEN 'claim_planet' THEN
            v_success := public.ai_claim_planet(ai_player);
            
        WHEN 'upgrade_ship' THEN
            v_success := public.ai_upgrade_ship(ai_player);
            
        WHEN 'upgrade_weapons' THEN
            v_success := public.ai_upgrade_weapons(ai_player);
            
        WHEN 'upgrade_engines' THEN
            v_success := public.ai_upgrade_engines(ai_player);
            
        WHEN 'buy_fighters' THEN
            v_success := public.ai_buy_fighters(ai_player);
            
        WHEN 'manage_planets' THEN
            v_success := public.ai_manage_planets(ai_player);
            
        WHEN 'patrol_territory' THEN
            v_success := public.ai_patrol_territory(ai_player);
            
        ELSE
            -- Default basic actions
            v_success := public.ai_basic_action(ai_player, action);
    END CASE;
    
    RETURN v_success;
END;
$$;

-- IMPORTANT: This system EXTENDS the existing AI system
-- It does NOT replace existing AI players or leaderboard integration
-- The existing AI players will continue to work exactly as before
-- Enhanced AI is OPTIONAL and can be enabled per universe

-- Add ai_actions_enabled setting to universe_settings (only if it doesn't exist)
ALTER TABLE universe_settings ADD COLUMN IF NOT EXISTS ai_actions_enabled BOOLEAN DEFAULT FALSE;

-- Set random personalities for existing AI players (only if they don't have one)
UPDATE players 
SET ai_personality = (
    CASE (RANDOM() * 5)::INTEGER
        WHEN 0 THEN 'trader'::ai_personality
        WHEN 1 THEN 'explorer'::ai_personality  
        WHEN 2 THEN 'warrior'::ai_personality
        WHEN 3 THEN 'colonizer'::ai_personality
        ELSE 'balanced'::ai_personality
    END
)
WHERE is_ai = TRUE AND ai_personality IS NULL;

-- Note: Enhanced AI is disabled by default
-- To enable enhanced AI for a universe, run:
-- UPDATE universe_settings SET ai_actions_enabled = TRUE WHERE universe_id = 'your-universe-id';
