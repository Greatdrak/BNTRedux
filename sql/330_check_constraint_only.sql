-- Check just the constraint
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(c.oid) AS constraint_definition
FROM pg_constraint c
WHERE c.conrelid = 'public.ships'::regclass
  AND conname = 'ships_energy_range';

-- Also check your current ship's energy situation
SELECT 
    s.id,
    s.player_id,
    s.energy,
    s.energy_max,
    s.power_lvl,
    p.handle
FROM public.ships s
JOIN public.players p ON p.id = s.player_id
WHERE p.is_ai = false
LIMIT 5;

