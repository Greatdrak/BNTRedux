-- Migration: 305_test_ai_functions.sql
-- Purpose: Test if AI decision and action functions exist and work

-- Test 1: Check if ai_make_decision function exists
SELECT 
  'ai_make_decision exists' as test,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p 
    JOIN pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'public' AND p.proname = 'ai_make_decision'
  ) THEN 'YES' ELSE 'NO' END as result;

-- Test 2: Check if ai_execute_action function exists  
SELECT 
  'ai_execute_action exists' as test,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p 
    JOIN pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'public' AND p.proname = 'ai_execute_action'
  ) THEN 'YES' ELSE 'NO' END as result;

-- Test 3: Try to call ai_make_decision for first AI player
SELECT 
  'ai_make_decision test' as test,
  decision
FROM ai_make_decision(
  (SELECT p.id FROM players p WHERE p.is_ai = true LIMIT 1),
  (SELECT id FROM universes WHERE name = 'Alpha' LIMIT 1)
);

