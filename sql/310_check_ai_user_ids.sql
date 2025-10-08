-- Migration: 310_check_ai_user_ids.sql
-- Purpose: Check AI player user_id values

SELECT 
  p.handle,
  p.user_id,
  p.is_ai,
  CASE WHEN p.user_id IS NULL THEN 'NULL' ELSE 'HAS_VALUE' END as user_id_status
FROM public.players p
WHERE p.is_ai = true
LIMIT 10;

