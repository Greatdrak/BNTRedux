-- Migration: 251_fix_duplicate_create_universe_functions.sql
-- Fix the duplicate create_universe functions issue

-- Drop the problematic create_universe function with 5 parameters
-- This is the one causing the warp limit error
DROP FUNCTION IF EXISTS public.create_universe(TEXT, INTEGER, NUMERIC, NUMERIC, INTEGER);

-- Ensure only the correct create_universe function exists (with trigger disabling)
-- The function with 2 parameters (name, sector_count) should be the only one
-- This function properly disables the warp limit trigger during creation

-- Verify the remaining function
SELECT 
    routine_name,
    routine_type,
    specific_name
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name = 'create_universe'
ORDER BY specific_name;
