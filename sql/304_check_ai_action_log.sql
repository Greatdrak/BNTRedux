-- Migration: 304_check_ai_action_log.sql
-- Purpose: Check what's being logged in ai_action_log

SELECT 
  action,
  outcome,
  message,
  created_at
FROM public.ai_action_log 
WHERE universe_id = (SELECT id FROM universes WHERE name = 'Alpha' LIMIT 1)
ORDER BY created_at DESC 
LIMIT 20;
