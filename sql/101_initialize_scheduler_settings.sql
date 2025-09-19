-- Initialize scheduler settings for existing universes
-- This sets up the scheduler timestamps and intervals for universes that don't have them yet

-- Update existing universe_settings records to have proper scheduler defaults
UPDATE public.universe_settings 
SET 
    turn_generation_interval_minutes = 3,
    turns_per_generation = 4,
    cycle_interval_minutes = 360,  -- 6 hours
    update_interval_minutes = 15,
    last_turn_generation = now() - interval '2 minutes',  -- Set to 2 minutes ago so next generation is soon
    last_cycle_event = now() - interval '5 hours',        -- Set to 5 hours ago so next cycle is in 1 hour
    last_update_event = now() - interval '14 minutes'     -- Set to 14 minutes ago so next update is in 1 minute
WHERE 
    turn_generation_interval_minutes IS NULL 
    OR last_turn_generation IS NULL 
    OR last_cycle_event IS NULL 
    OR last_update_event IS NULL;

-- Create default settings for any universes that don't have universe_settings yet
INSERT INTO public.universe_settings (
    universe_id,
    turn_generation_interval_minutes,
    turns_per_generation,
    cycle_interval_minutes,
    update_interval_minutes,
    last_turn_generation,
    last_cycle_event,
    last_update_event
)
SELECT 
    u.id,
    3,  -- turn_generation_interval_minutes
    4,  -- turns_per_generation
    360,  -- cycle_interval_minutes (6 hours)
    15,  -- update_interval_minutes
    now() - interval '2 minutes',  -- last_turn_generation
    now() - interval '5 hours',     -- last_cycle_event
    now() - interval '14 minutes'   -- last_update_event
FROM public.universes u
LEFT JOIN public.universe_settings us ON u.id = us.universe_id
WHERE us.universe_id IS NULL;

-- Verify the setup
SELECT 
    u.name as universe_name,
    us.turn_generation_interval_minutes,
    us.turns_per_generation,
    us.cycle_interval_minutes,
    us.update_interval_minutes,
    us.last_turn_generation,
    us.last_cycle_event,
    us.last_update_event
FROM public.universes u
LEFT JOIN public.universe_settings us ON u.id = us.universe_id
ORDER BY u.created_at;
