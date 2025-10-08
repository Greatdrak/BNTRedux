-- Check ships table structure for energy constraint
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(c.oid) AS constraint_definition
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE n.nspname = 'public' 
  AND c.conrelid = 'public.ships'::regclass
  AND conname LIKE '%energy%';

-- Also check all columns on ships table
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'ships'
  AND column_name LIKE '%energy%';

