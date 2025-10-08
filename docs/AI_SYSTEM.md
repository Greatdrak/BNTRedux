# AI System Documentation

## Overview
The BNT Redux AI system provides intelligent computer-controlled players that can perform complex game actions including trading, exploration, planet management, and strategic decision-making. The system has been recently improved to address performance issues and prevent AI players from getting stuck in loops.

## Current Status (Updated 2025-01-28)
- ✅ **Performance Optimized**: Logging disabled, database indexes added
- ✅ **Error Handling**: Robust error handling prevents AI crashes
- ✅ **Decision Logic**: Improved decision-making with weighted priorities
- ✅ **Action Execution**: Better validation and fallback mechanisms
- ⚠️ **Memory System**: Basic implementation, needs enhancement for learning
- ⚠️ **Personality System**: Simplified, needs expansion for diverse behaviors

## Architecture

### Core Components

#### 1. AI Player Types
AI players are defined by their personality type, which influences their behavior:

- **`trader`** - Focuses on buying low, selling high, optimizing trade routes
- **`explorer`** - Prioritizes discovering new sectors and claiming planets
- **`warrior`** - Aggressive, seeks combat and territorial expansion
- **`colonizer`** - Focuses on planet development and resource production
- **`balanced`** - Well-rounded approach, adapts to current situation

#### 2. AI Memory System
Each AI player has persistent memory stored in the `ai_player_memory` table:

```sql
CREATE TABLE ai_player_memory (
  id UUID PRIMARY KEY,
  player_id UUID UNIQUE REFERENCES players(id),
  current_goal TEXT,
  target_sector UUID REFERENCES sectors(id),
  target_planet UUID REFERENCES planets(id),
  last_action TEXT,
  action_count INTEGER DEFAULT 0,
  efficiency_score NUMERIC DEFAULT 0.0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

#### 3. Decision Making Process
The AI system uses a multi-layered decision-making process:

1. **Situation Assessment** - Analyze current state (credits, cargo, location, threats)
2. **Goal Selection** - Choose primary objective based on personality and situation
3. **Action Planning** - Determine specific actions to achieve the goal
4. **Execution** - Perform actions using existing game functions
5. **Learning** - Update memory and efficiency scores based on results

## AI Functions

### Core AI Functions (Updated)

#### `run_ai_player_actions(p_universe_id)`
Main entry point for AI system. Processes all AI players in a universe with improved error handling.

**Process:**
1. Count total AI players and those with turns
2. For each AI player (ordered by turns and credits):
   - Make decision using `ai_make_decision()`
   - Execute action using `ai_execute_action()`
   - Track success/failure statistics
3. Return comprehensive results with success rates

**Returns:** JSON with detailed statistics including success rates and action breakdown

#### `ai_make_decision(p_player_id)`
Core decision-making function with weighted priority system.

**Decision Logic (Priority Order):**
1. **No Turns** → `wait`
2. **Unclaimed Planets + Credits ≥ 10,000** → `claim_planet`
3. **Commodity Ports + Credits ≥ 500** → `trade`
4. **Special Ports + Credits ≥ 2,000 + Hull < 5** → `upgrade_ship`
5. **Available Warps** → `explore`
6. **Credits < 100** → `emergency_trade`
7. **Fallback** → `wait`

**Returns:** Action string (`claim_planet`, `trade`, `upgrade_ship`, `explore`, `emergency_trade`, `wait`)

#### `ai_execute_action(p_player_id, p_universe_id, p_action)`
Robust action execution with comprehensive error handling.

**Supported Actions:**
- `claim_planet` - Claim first unclaimed planet in current sector
- `trade` - Buy ore at commodity ports (not special ports)
- `upgrade_ship` - Upgrade hull at special ports
- `explore` - Move to random connected sector via warps
- `emergency_trade` - Sell cargo when credits are low
- `wait` - No action taken

**Error Handling:** All actions wrapped in try-catch blocks with graceful fallbacks

### Specialized AI Functions

#### `ai_optimize_trading(p_player_id)`
Optimizes trading based on current cargo and port prices.

**Logic:**
1. Analyze current cargo and credits
2. Find best trade opportunities in current sector
3. Execute profitable trades
4. Update memory with trade results

#### `ai_strategic_explore(p_player_id)`
Strategic exploration to find valuable sectors and planets.

**Logic:**
1. Identify unexplored sectors
2. Prioritize sectors with high value (ports, unclaimed planets)
3. Move to target sector
4. Claim valuable planets
5. Update exploration memory

#### `ai_claim_planet(p_player_id)`
Intelligent planet claiming based on value assessment.

**Logic:**
1. Scan current sector for unclaimed planets
2. Assess planet value (resources, strategic location)
3. Claim highest value planet
4. Update planet management memory

#### `ai_manage_planets(p_player_id)`
Manages owned planets for optimal resource production.

**Logic:**
1. Get list of owned planets
2. Analyze production needs
3. Optimize production allocation
4. Transfer resources as needed
5. Update planet management memory

#### `ai_upgrade_ship(p_player_id)`
Strategic ship upgrades based on current needs.

**Logic:**
1. Assess current ship capabilities
2. Identify upgrade priorities based on personality
3. Execute upgrades within budget
4. Update ship management memory

## AI Behavior Patterns

### Trader AI
- **Primary Goal**: Maximize profit through trading
- **Behavior**: 
  - Seeks ports with good buy/sell opportunities
  - Maintains diverse cargo for flexibility
  - Avoids risky sectors
  - Focuses on high-profit trade routes

### Explorer AI
- **Primary Goal**: Discover new territory and claim planets
- **Behavior**:
  - Moves to unexplored sectors
  - Claims unclaimed planets
  - Maps warp connections
  - Avoids combat when possible

### Warrior AI
- **Primary Goal**: Territorial expansion and combat
- **Behavior**:
  - Seeks combat opportunities
  - Upgrades weapons and armor
  - Claims strategic planets
  - Attacks weaker players

### Colonizer AI
- **Primary Goal**: Develop and manage planets
- **Behavior**:
  - Focuses on planet development
  - Optimizes resource production
  - Builds defensive structures
  - Manages colonist populations

### Balanced AI
- **Primary Goal**: Adapt to current situation
- **Behavior**:
  - Switches strategies based on opportunities
  - Maintains flexible approach
  - Balances all aspects of gameplay
- **Adaptive Logic**:
  - Low credits → Focus on trading
  - Unexplored sectors → Focus on exploration
  - Weak defenses → Focus on upgrades
  - Available planets → Focus on claiming

## AI Memory and Learning

### Memory Structure
Each AI player maintains persistent memory:

- **`current_goal`** - Current primary objective
- **`target_sector`** - Target sector for movement
- **`target_planet`** - Target planet for actions
- **`last_action`** - Last action taken
- **`action_count`** - Total actions taken
- **`efficiency_score`** - Performance rating

### Learning Mechanism
AI players learn from their actions:

1. **Success Tracking** - Record successful actions
2. **Efficiency Scoring** - Rate performance based on results
3. **Strategy Adaptation** - Adjust behavior based on success rates
4. **Memory Updates** - Store lessons learned

### Efficiency Scoring
AI efficiency is calculated based on:
- **Credits gained/lost** - Financial performance
- **Planets claimed** - Territorial expansion
- **Resources produced** - Economic output
- **Combat success** - Military performance
- **Exploration progress** - Discovery achievements

## Integration with Game Systems

### Cron Integration
The AI system integrates with the cron job system:

```sql
-- Cron wrapper function
CREATE OR REPLACE FUNCTION cron_run_ai_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if enhanced AI is enabled
  IF EXISTS (
    SELECT 1 FROM universe_settings 
    WHERE universe_id = p_universe_id 
    AND ai_actions_enabled = true
  ) THEN
    -- Run enhanced AI system
    RETURN run_enhanced_ai_actions(p_universe_id);
  ELSE
    -- Run basic AI actions
    RETURN run_ai_player_actions(p_universe_id);
  END IF;
END;
$$;
```

### Turn Tracking
AI actions consume turns like human players:

```sql
-- Track turn usage for AI actions
CREATE OR REPLACE FUNCTION track_turn_spent(p_player_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE players 
  SET turns = GREATEST(0, turns - 1),
      turns_spent = turns_spent + 1
  WHERE id = p_player_id;
END;
$$;
```

### Game Function Integration
AI players use the same game functions as human players:
- `game_move()` - Movement
- `game_trade()` - Trading
- `game_planet_claim()` - Planet claiming
- `game_ship_upgrade()` - Ship upgrades
- `game_planet_transfer()` - Resource management

## Performance Optimization

### Batch Processing
AI actions are processed in batches to optimize performance:

1. **Load all AI players** in a single query
2. **Process decisions** in memory
3. **Execute actions** in batches
4. **Update memory** in bulk operations

### Memory Optimization
- **Lazy loading** - Load memory only when needed
- **Batch updates** - Update multiple AI memories at once
- **Efficient queries** - Use indexes and optimized joins

### Turn Management
- **Turn limits** - AI players have unlimited turns but track usage
- **Action throttling** - Limit actions per AI per tick
- **Priority queuing** - Process high-priority AI first

## Monitoring and Debugging

### AI Statistics
The system provides comprehensive AI statistics:

```sql
CREATE OR REPLACE FUNCTION get_ai_statistics(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stats JSON;
BEGIN
  SELECT json_build_object(
    'total_ai_players', COUNT(*),
    'by_personality', json_object_agg(ai_personality, count),
    'total_credits', SUM(s.credits),
    'total_planets', COUNT(DISTINCT p.id),
    'average_efficiency', AVG(m.efficiency_score)
  ) INTO v_stats
  FROM players pl
  LEFT JOIN ships s ON s.player_id = pl.id
  LEFT JOIN planets p ON p.owner_player_id = pl.id
  LEFT JOIN ai_player_memory m ON m.player_id = pl.id
  WHERE pl.universe_id = p_universe_id
    AND pl.is_ai = true;
    
  RETURN v_stats;
END;
$$;
```

### Debug Information
AI actions include detailed debug information:
- **Action taken** - What the AI decided to do
- **Reasoning** - Why the AI made that decision
- **Results** - What happened as a result
- **Memory updates** - How the AI's memory changed

### Logging
AI actions are logged for monitoring:
- **Action logs** - Record of all AI actions
- **Performance metrics** - Efficiency and success rates
- **Error handling** - Failed actions and recovery

## Configuration

### Universe Settings
AI behavior can be configured per universe:

```sql
-- AI settings in universe_settings table
ai_actions_enabled BOOLEAN DEFAULT true,
max_ai_actions_per_tick INTEGER DEFAULT 10,
ai_turn_cost INTEGER DEFAULT 1,
ai_efficiency_threshold NUMERIC DEFAULT 0.5
```

### Personality Weights
Each AI personality has configurable behavior weights:
- **Aggression** - How likely to engage in combat
- **Exploration** - How likely to explore new areas
- **Trading** - How likely to focus on trading
- **Colonization** - How likely to claim planets
- **Upgrading** - How likely to upgrade equipment

## Recent Improvements (2025-01-28)

### Performance Optimizations
- **Logging Disabled**: Removed excessive AI action logging that was causing database bottlenecks
- **Database Indexes**: Added critical indexes on frequently queried tables (players, sectors, warps, ports, planets)
- **SWR Optimization**: Increased deduping interval and reduced unnecessary refetches
- **Error Handling**: Added comprehensive try-catch blocks to prevent AI crashes

### Decision Logic Improvements
- **Weighted Priorities**: Implemented priority-based decision making instead of random choices
- **Resource Awareness**: AI now considers credits, turns, and ship capabilities in decisions
- **Port Type Validation**: AI correctly identifies commodity vs special ports
- **Emergency Actions**: Added emergency trading for low-credit situations

### Action Execution Fixes
- **Validation**: All actions now validate prerequisites before execution
- **Fallback Mechanisms**: Graceful handling of failed actions with appropriate fallbacks
- **Resource Checks**: Proper validation of credits, turns, and cargo space
- **Sector Validation**: Movement actions verify warp connections exist

### Monitoring & Debugging
- **Health Checks**: New `check_ai_health()` function for system monitoring
- **Success Rates**: AI actions now track and report success rates
- **Action Breakdown**: Detailed statistics on action types and outcomes
- **Error Tracking**: Better error reporting and debugging information

### Known Limitations
- **Memory System**: Basic implementation, needs enhancement for learning and adaptation
- **Personality System**: Simplified decision logic, needs expansion for diverse AI behaviors
- **Strategic Planning**: AI lacks long-term planning and goal persistence
- **Cooperative AI**: No AI-to-AI interaction or cooperation mechanisms

## Troubleshooting

### Common Issues (Updated)

1. **AI not taking actions** 
   - ✅ **Fixed**: Check if AI is enabled in universe settings
   - ✅ **Fixed**: Verify AI players have turns available
   - ✅ **Fixed**: Check for database connection issues

2. **AI getting stuck in loops**
   - ✅ **Fixed**: Improved decision logic with weighted priorities
   - ✅ **Fixed**: Better fallback mechanisms prevent infinite loops
   - ✅ **Fixed**: Emergency actions for low-credit situations

3. **Poor AI performance**
   - ✅ **Fixed**: Performance optimizations applied (logging disabled, indexes added)
   - ✅ **Fixed**: Better error handling prevents crashes
   - ✅ **Fixed**: Success rate tracking for monitoring

4. **High resource usage**
   - ✅ **Fixed**: Excessive logging removed
   - ✅ **Fixed**: Database indexes added for faster queries
   - ✅ **Fixed**: Optimized SWR configuration

### Debug Commands (Updated)

```sql
-- Check AI player status
SELECT p.handle, p.turns, s.credits, m.current_goal, m.efficiency_score
FROM players p
LEFT JOIN ships s ON s.player_id = p.id
LEFT JOIN ai_player_memory m ON m.player_id = p.id
WHERE p.is_ai = true;

-- Check AI health
SELECT check_ai_health('universe_id');

-- Run AI actions manually
SELECT run_ai_player_actions('universe_id');

-- Get AI debug snapshot
SELECT get_ai_debug_snapshot('universe_id');
```

### Performance Monitoring

The system now provides comprehensive monitoring:

```sql
-- AI Health Check
SELECT check_ai_health('universe_id');
-- Returns: total_ai_players, active_ai_players, health_status, average_efficiency

-- AI Action Statistics
SELECT run_ai_player_actions('universe_id');
-- Returns: actions_taken, success_rate, action_breakdown
```
