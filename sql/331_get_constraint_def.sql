-- Get the exact constraint
SELECT 
    conname,
    pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.conrelid = 'public.ships'::regclass
  AND conname = 'ships_energy_range';




