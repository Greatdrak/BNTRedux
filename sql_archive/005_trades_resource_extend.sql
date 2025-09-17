-- Extend trades.resource CHECK constraint to allow upgrade/repair audit values
-- How to apply: Run this file once in Supabase SQL Editor after previous migrations

ALTER TABLE trades DROP CONSTRAINT IF EXISTS trades_resource_check;

ALTER TABLE trades
ADD CONSTRAINT trades_resource_check
CHECK (
  resource IN (
    'ore', 'organics', 'goods', 'energy',
    'fighters', 'torpedoes', 'hull_repair'
  )
);


