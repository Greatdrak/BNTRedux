-- Migration: Give AI players immediate turns
-- Since we have the communism boost equalizer, AI players should always have turns available
-- to ensure they can take actions when the cron runs

-- Give all AI players 1000 turns immediately
UPDATE public.players
SET turns = turns + 1000
WHERE is_ai = true;

