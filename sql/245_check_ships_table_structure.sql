-- Check the current structure of the ships table to see what columns exist
SELECT 
    column_name, 
    data_type, 
    is_nullable, 
    column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name = 'ships'
ORDER BY ordinal_position;
