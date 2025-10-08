-- Check the exact constraint definition
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(c.oid) AS constraint_definition
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE n.nspname = 'public' 
  AND c.conrelid = 'public.ships'::regclass
  AND conname = 'ships_energy_range';

-- Also check if energy_max is a generated column or regular column
SELECT 
    attname AS column_name,
    attgenerated AS is_generated,
    pg_get_expr(adbin, adrelid) AS default_or_generated_expr
FROM pg_attribute a
LEFT JOIN pg_attrdef ad ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
WHERE a.attrelid = 'public.ships'::regclass
  AND attname IN ('energy', 'energy_max')
ORDER BY attname;

