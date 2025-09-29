-- Migration: 246_fix_register_ship_creation.sql
-- Fix the ship creation in register API to include all required columns

-- First, let's check what columns are actually required vs optional in the ships table
-- This will help us identify any missing columns in the register API

SELECT 
    column_name,
    is_nullable,
    column_default,
    data_type
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name = 'ships'
AND column_name IN (
    'armor_lvl', 'beam_lvl', 'cloak_lvl', 'power_lvl', 
    'torp_launcher_lvl', 'armor', 'energy', 'ore', 'organics', 
    'goods', 'colonists', 'is_ai'
)
ORDER BY column_name;
