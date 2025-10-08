-- Migration: 355_add_score_column.sql
-- Purpose: Add score column to players table and create trigger to auto-update

-- Add score column to players table
ALTER TABLE public.players
ADD COLUMN IF NOT EXISTS score BIGINT DEFAULT 0;

-- Create index on score for faster queries
CREATE INDEX IF NOT EXISTS idx_players_score ON public.players(score DESC);

-- Create function to update player score
CREATE OR REPLACE FUNCTION public.update_player_score()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_score BIGINT;
BEGIN
  -- Calculate score for the player
  v_score := calculate_player_score(NEW.id);
  
  -- Update the score column
  NEW.score := v_score;
  
  RETURN NEW;
END;
$$;

-- Create trigger to auto-update score when player data changes
DROP TRIGGER IF EXISTS trigger_update_player_score ON public.players;
CREATE TRIGGER trigger_update_player_score
  BEFORE UPDATE ON public.players
  FOR EACH ROW
  EXECUTE FUNCTION update_player_score();

-- Create trigger to update score when ship data changes (affects score calculation)
CREATE OR REPLACE FUNCTION public.update_player_score_from_ship()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_score BIGINT;
BEGIN
  -- Calculate score for the player who owns this ship
  v_score := calculate_player_score(NEW.player_id);
  
  -- Update the score in players table
  UPDATE public.players
  SET score = v_score
  WHERE id = NEW.player_id;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_player_score_from_ship ON public.ships;
CREATE TRIGGER trigger_update_player_score_from_ship
  AFTER UPDATE ON public.ships
  FOR EACH ROW
  EXECUTE FUNCTION update_player_score_from_ship();

-- Create trigger to update score when planet data changes
CREATE OR REPLACE FUNCTION public.update_player_score_from_planet()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_score BIGINT;
BEGIN
  -- Update score for the old owner if there was one
  IF OLD.owner_player_id IS NOT NULL THEN
    v_score := calculate_player_score(OLD.owner_player_id);
    UPDATE public.players SET score = v_score WHERE id = OLD.owner_player_id;
  END IF;
  
  -- Update score for the new owner if there is one
  IF NEW.owner_player_id IS NOT NULL THEN
    v_score := calculate_player_score(NEW.owner_player_id);
    UPDATE public.players SET score = v_score WHERE id = NEW.owner_player_id;
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_player_score_from_planet ON public.planets;
CREATE TRIGGER trigger_update_player_score_from_planet
  AFTER UPDATE OR INSERT ON public.planets
  FOR EACH ROW
  EXECUTE FUNCTION update_player_score_from_planet();

-- Populate scores for all existing players
UPDATE public.players
SET score = calculate_player_score(id)
WHERE score = 0 OR score IS NULL;

-- Create a manual refresh function for bulk updates
CREATE OR REPLACE FUNCTION public.refresh_all_player_scores(p_universe_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.players
  SET score = calculate_player_score(id)
  WHERE universe_id = p_universe_id;
END;
$$;

