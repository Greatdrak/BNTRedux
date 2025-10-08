-- Migration: 299_init_ai_memory.sql
-- Purpose: Ensure all AI players have a memory row and a default starting goal

-- Insert missing memory rows
INSERT INTO public.ai_player_memory (player_id, current_goal)
SELECT p.id, 'explore'
FROM public.players p
LEFT JOIN public.ai_player_memory m ON m.player_id = p.id
WHERE p.is_ai = TRUE
  AND m.player_id IS NULL;

-- Backfill null goals to 'explore'
UPDATE public.ai_player_memory
SET current_goal = 'explore'
WHERE current_goal IS NULL;
