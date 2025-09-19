-- Move credits from players table to ships table
-- This makes more sense as credits are ship-specific resources

-- Add credits column to ships table
ALTER TABLE public.ships 
ADD COLUMN IF NOT EXISTS credits bigint DEFAULT 0 CHECK (credits >= 0);

-- Migrate existing credits from players to ships
UPDATE public.ships 
SET credits = COALESCE(p.credits, 0)
FROM public.players p
WHERE ships.player_id = p.id;

-- Remove credits column from players table (after migration)
ALTER TABLE public.players 
DROP COLUMN IF EXISTS credits;

-- Update the transfer API logic will be handled in the code
-- No additional database changes needed for the transfer functionality
