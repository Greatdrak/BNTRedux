-- Debug script to check what's actually in the ships table

-- Check ships table structure
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default,
    character_maximum_length
FROM information_schema.columns 
WHERE table_name = 'ships' AND table_schema = 'public'
ORDER BY ordinal_position;

-- Check if there are any ships with credits
SELECT COUNT(*) as total_ships, 
       COUNT(credits) as ships_with_credits_column
FROM public.ships;

-- Show sample ship data
SELECT id, name, credits, ore, organics, goods, energy 
FROM public.ships 
LIMIT 3;
