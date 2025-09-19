-- Remove turn_cap column from players table
-- Turn cap is now managed via universe_settings.max_accumulated_turns

-- Drop the turn_cap column from players table
ALTER TABLE public.players DROP COLUMN IF EXISTS turn_cap;

-- Update any remaining references in old RPCs or functions
-- (The main RPCs were already updated in 110_fix_turn_cap_universe_setting.sql)
