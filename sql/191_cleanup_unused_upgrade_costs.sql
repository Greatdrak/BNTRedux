-- Cleanup unused upgrade_costs table and get_upgrade_cost function
-- These are no longer used since we switched to direct BNT exponential formulas

-- Drop the unused function
DROP FUNCTION IF EXISTS public.get_upgrade_cost(integer);

-- Drop the unused table
DROP TABLE IF EXISTS public.upgrade_costs;

-- Note: The game_ship_upgrade function now uses direct BNT exponential formulas:
-- v_cost := 1000 * POWER(2, v_ship.engine_lvl);
-- v_cost := 1000 * POWER(2, v_ship.hull_lvl);
-- etc.
