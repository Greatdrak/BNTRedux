-- Migration: 311_debug_ai_universe_mismatch.sql
-- Purpose: Debug AI player universe vs function call

-- Check AI player universe
SELECT 
  p.handle,
  p.user_id,
  u.name as universe_name,
  u.id as universe_id
FROM public.players p
JOIN public.universes u ON u.id = p.universe_id
WHERE p.is_ai = true
LIMIT 5;

-- Check what universe we're calling the function with
SELECT 
  name,
  id as universe_id
FROM public.universes
ORDER BY created_at;
