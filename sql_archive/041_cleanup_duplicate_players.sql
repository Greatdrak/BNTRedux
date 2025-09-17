-- Cleanup Duplicate Players
-- This script removes duplicate players created by the auto-creation logic
-- Run this in Supabase SQL Editor to clean up the database

-- First, let's see what players we have
SELECT 
  p.id,
  p.handle,
  p.user_id,
  u.name as universe_name,
  p.created_at
FROM players p
JOIN universes u ON p.universe_id = u.id
ORDER BY p.created_at DESC;

-- Remove players with auto-generated handles (Player_* pattern)
-- Keep only the most recent player for each user_id in each universe
WITH ranked_players AS (
  SELECT 
    p.*,
    ROW_NUMBER() OVER (
      PARTITION BY p.user_id, p.universe_id 
      ORDER BY p.created_at DESC
    ) as rn
  FROM players p
  WHERE p.handle LIKE 'Player_%'
)
DELETE FROM players 
WHERE id IN (
  SELECT id FROM ranked_players WHERE rn > 1
);

-- Also clean up any orphaned ships and inventories
DELETE FROM ships 
WHERE player_id NOT IN (SELECT id FROM players);

DELETE FROM inventories 
WHERE player_id NOT IN (SELECT id FROM players);

-- Show remaining players
SELECT 
  p.id,
  p.handle,
  p.user_id,
  u.name as universe_name,
  p.created_at
FROM players p
JOIN universes u ON p.universe_id = u.id
ORDER BY p.created_at DESC;
