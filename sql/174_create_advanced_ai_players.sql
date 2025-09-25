-- Create advanced AI players with higher tech levels
-- This adds variety and challenge to the game

-- First, create some sectors if they don't exist
INSERT INTO sectors (id, universe_id, number)
SELECT 
  gen_random_uuid() as id,
  '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid as universe_id,
  generate_series(1, 5) as number
ON CONFLICT (universe_id, number) DO NOTHING;

-- Create 10 advanced AI players with varying tech levels
INSERT INTO players (user_id, handle, universe_id, is_ai, turns, current_sector)
SELECT 
  gen_random_uuid() as user_id,
  'AI_' || CASE 
    WHEN row_number() OVER () = 1 THEN 'Alpha'
    WHEN row_number() OVER () = 2 THEN 'Beta'
    WHEN row_number() OVER () = 3 THEN 'Gamma'
    WHEN row_number() OVER () = 4 THEN 'Delta'
    WHEN row_number() OVER () = 5 THEN 'Epsilon'
    WHEN row_number() OVER () = 6 THEN 'Zeta'
    WHEN row_number() OVER () = 7 THEN 'Eta'
    WHEN row_number() OVER () = 8 THEN 'Theta'
    WHEN row_number() OVER () = 9 THEN 'Iota'
    ELSE 'Kappa'
  END as handle,
  '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid as universe_id,
  true as is_ai,
  1000 + (random() * 2000)::integer as turns,
  (SELECT id FROM sectors WHERE universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid ORDER BY number LIMIT 1 OFFSET (random() * 5)::integer) as current_sector
FROM generate_series(1, 10);

-- Create ships for the AI players with proper tech levels and corresponding values
WITH ai_players AS (
  SELECT id, handle FROM players 
  WHERE is_ai = true 
  AND handle LIKE 'AI_%'
  AND universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid
  ORDER BY created_at DESC
  LIMIT 10
),
tech_levels AS (
  SELECT 
    ap.id as player_id,
    ap.handle,
    -- Tech levels: Random between 1-8 for most, some higher
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer -- 10% chance for low tech (1-3)
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer -- 70% chance for mid tech (3-6)
      ELSE 6 + (random() * 5)::integer -- 20% chance for high tech (6-10)
    END as engine_lvl,
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer
      ELSE 6 + (random() * 5)::integer
    END as comp_lvl,
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer
      ELSE 6 + (random() * 5)::integer
    END as sensor_lvl,
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer
      ELSE 6 + (random() * 5)::integer
    END as power_lvl,
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer
      ELSE 6 + (random() * 5)::integer
    END as beam_lvl,
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer
      ELSE 6 + (random() * 5)::integer
    END as torp_launcher_lvl,
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer
      ELSE 6 + (random() * 5)::integer
    END as shield_lvl,
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer
      ELSE 6 + (random() * 5)::integer
    END as hull_lvl,
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer
      ELSE 6 + (random() * 5)::integer
    END as cloak_lvl,
    CASE 
      WHEN random() < 0.1 THEN 1 + (random() * 3)::integer
      WHEN random() < 0.7 THEN 3 + (random() * 4)::integer
      ELSE 6 + (random() * 5)::integer
    END as armor_lvl
  FROM ai_players ap
)
INSERT INTO ships (
  player_id,
  name,
  engine_lvl,
  comp_lvl,
  sensor_lvl,
  power_lvl,
  beam_lvl,
  torp_launcher_lvl,
  shield_lvl,
  hull_lvl,
  cloak_lvl,
  armor_lvl,
  hull_max,
  hull,
  shield,
  cargo,
  fighters,
  torpedoes,
  energy,
  energy_max,
  armor,
  credits,
  ore,
  organics,
  goods,
  colonists
)
SELECT 
  tl.player_id,
  tl.handle || '_Ship' as name,
  tl.engine_lvl,
  tl.comp_lvl,
  tl.sensor_lvl,
  tl.power_lvl,
  tl.beam_lvl,
  tl.torp_launcher_lvl,
  tl.shield_lvl,
  tl.hull_lvl,
  tl.cloak_lvl,
  tl.armor_lvl,
  -- Values based on tech levels (using BNT formulas)
  -- Formula: 100 * (1.5^tech_level) where tech_level = hull_lvl - 1
  100 * POWER(1.5, tl.hull_lvl - 1)::integer as hull_max,
  100 * POWER(1.5, tl.hull_lvl - 1)::integer as hull,
  20 * tl.shield_lvl as shield,
  -- Cargo capacity based on hull_lvl
  CASE 
    WHEN tl.hull_lvl = 1 THEN 1000
    WHEN tl.hull_lvl = 2 THEN 3500
    WHEN tl.hull_lvl = 3 THEN 7224
    WHEN tl.hull_lvl = 4 THEN 10000
    WHEN tl.hull_lvl = 5 THEN 13162
    ELSE FLOOR(1000 * POWER(tl.hull_lvl, 1.8))
  END as cargo,
  -- Other values
  100 + (random() * 1900)::integer as fighters,
  50 + (random() * 450)::integer as torpedoes,
  1000 + (random() * 9000)::integer as energy,
  1000 + (random() * 9000)::integer as energy_max,
  (random() * 1000)::integer as armor,
  100000 + (random() * 9900000)::integer as credits,
  (random() * 10000)::integer as ore,
  (random() * 10000)::integer as organics,
  (random() * 10000)::integer as goods,
  (random() * 1000)::integer as colonists
FROM tech_levels tl;

-- Create some elite AI players with very high tech levels (boss-level)
INSERT INTO players (user_id, handle, universe_id, is_ai, turns, current_sector)
SELECT 
  gen_random_uuid() as user_id,
  'AI_' || CASE 
    WHEN row_number() OVER () = 1 THEN 'Destroyer'
    WHEN row_number() OVER () = 2 THEN 'Battleship'
    ELSE 'Dreadnought'
  END as handle,
  '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid as universe_id,
  true as is_ai,
  5000 as turns,
  (SELECT id FROM sectors WHERE universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid ORDER BY number LIMIT 1 OFFSET (random() * 5)::integer) as current_sector
FROM generate_series(1, 3);

-- Create elite ships for the boss AI players
WITH elite_players AS (
  SELECT id, handle FROM players 
  WHERE is_ai = true 
  AND handle IN ('AI_Destroyer', 'AI_Battleship', 'AI_Dreadnought')
  AND universe_id = '34ef41a9-a3a9-42b1-a174-3c55f70236da'::uuid
),
elite_tech_levels AS (
  SELECT 
    ep.id as player_id,
    ep.handle,
    -- Elite tech levels (12-15)
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as engine_lvl,
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as comp_lvl,
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as sensor_lvl,
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as power_lvl,
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as beam_lvl,
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as torp_launcher_lvl,
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as shield_lvl,
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as hull_lvl,
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as cloak_lvl,
    CASE ep.handle
      WHEN 'AI_Destroyer' THEN 12
      WHEN 'AI_Battleship' THEN 13
      WHEN 'AI_Dreadnought' THEN 15
    END as armor_lvl
  FROM elite_players ep
)
INSERT INTO ships (
  player_id,
  name,
  engine_lvl,
  comp_lvl,
  sensor_lvl,
  power_lvl,
  beam_lvl,
  torp_launcher_lvl,
  shield_lvl,
  hull_lvl,
  cloak_lvl,
  armor_lvl,
  hull_max,
  hull,
  shield,
  cargo,
  fighters,
  torpedoes,
  energy,
  energy_max,
  armor,
  credits,
  ore,
  organics,
  goods,
  colonists
)
SELECT 
  etl.player_id,
  etl.handle || '_Elite' as name,
  etl.engine_lvl,
  etl.comp_lvl,
  etl.sensor_lvl,
  etl.power_lvl,
  etl.beam_lvl,
  etl.torp_launcher_lvl,
  etl.shield_lvl,
  etl.hull_lvl,
  etl.cloak_lvl,
  etl.armor_lvl,
  -- Elite values based on tech levels
  -- Formula: 100 * (1.5^tech_level) where tech_level = hull_lvl - 1
  100 * POWER(1.5, etl.hull_lvl - 1)::integer as hull_max,
  100 * POWER(1.5, etl.hull_lvl - 1)::integer as hull,
  20 * etl.shield_lvl as shield,
  -- Cargo capacity based on hull_lvl
  CASE 
    WHEN etl.hull_lvl = 1 THEN 1000
    WHEN etl.hull_lvl = 2 THEN 3500
    WHEN etl.hull_lvl = 3 THEN 7224
    WHEN etl.hull_lvl = 4 THEN 10000
    WHEN etl.hull_lvl = 5 THEN 13162
    ELSE FLOOR(1000 * POWER(etl.hull_lvl, 1.8))
  END as cargo,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 5000
    WHEN 'AI_Battleship' THEN 8000
    WHEN 'AI_Dreadnought' THEN 15000
  END as fighters,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 1000
    WHEN 'AI_Battleship' THEN 2000
    WHEN 'AI_Dreadnought' THEN 5000
  END as torpedoes,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 50000
    WHEN 'AI_Battleship' THEN 100000
    WHEN 'AI_Dreadnought' THEN 200000
  END as energy,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 50000
    WHEN 'AI_Battleship' THEN 100000
    WHEN 'AI_Dreadnought' THEN 200000
  END as energy_max,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 5000
    WHEN 'AI_Battleship' THEN 10000
    WHEN 'AI_Dreadnought' THEN 25000
  END as armor,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 1000000
    WHEN 'AI_Battleship' THEN 2000000
    WHEN 'AI_Dreadnought' THEN 5000000
  END as credits,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 10000
    WHEN 'AI_Battleship' THEN 20000
    WHEN 'AI_Dreadnought' THEN 50000
  END as ore,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 10000
    WHEN 'AI_Battleship' THEN 20000
    WHEN 'AI_Dreadnought' THEN 50000
  END as organics,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 10000
    WHEN 'AI_Battleship' THEN 20000
    WHEN 'AI_Dreadnought' THEN 50000
  END as goods,
  CASE etl.handle
    WHEN 'AI_Destroyer' THEN 10000
    WHEN 'AI_Battleship' THEN 20000
    WHEN 'AI_Dreadnought' THEN 50000
  END as colonists
FROM elite_tech_levels etl;